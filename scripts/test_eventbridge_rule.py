"""
Trigger an ECS task-level failure on purpose to test an EventBridge rule.

Flow
----
1) Register a temporary task definition with a nonexistent image tag.
2) Run one task on the target cluster and VPC config.
3) Wait until STOPPED with a waiter, then poll DescribeTasks for stopCode.
4) Print lastStatus, stopCode, stoppedReason, and container reasons.
5) Cleanup: deregister and delete the task definition revision.
"""

import argparse
import logging
import random
import string
import sys
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Literal, Optional, Tuple

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from mypy_boto3_ecs import ECSClient
from mypy_boto3_ecs.type_defs import (
    DeleteTaskDefinitionsResponseTypeDef,
    DeregisterTaskDefinitionResponseTypeDef,
    DescribeTasksResponseTypeDef,
    FailureTypeDef,
    RegisterTaskDefinitionResponseTypeDef,
    RunTaskResponseTypeDef,
    TaskTypeDef,
)
from mypy_boto3_ecs.waiter import TasksStoppedWaiter

logger = logging.getLogger("Trigger ECS Fargate Task")
logger.setLevel(logging.INFO)
logger.addHandler(logging.StreamHandler(stream=sys.stdout))


@dataclass(frozen=True)
class ECSConfig(object):
    """
    Configuration for triggering an ECS task-level failure.

    Parameters
    ----------
    cluster_arn : str
        Target ECS cluster ARN.
    execution_role_arn : str
        ARN of the ECS task execution role.
    subnets : List[str]
        Subnet IDs for awsvpc networking.
    security_groups : List[str]
        Security group IDs for awsvpc networking.
    launch_type : str
        ECS launch type.
    cpu : str
        Task-level CPU units for Fargate. Example: "256".
    memory : str
        Task-level memory for Fargate. Example: "512" or "1GB".
    family_prefix : str
        Prefix for the temporary task definition family.
    region : str
        AWS region.
    profile : str
        AWS profile name.
    assign_public_ip : bool
        Whether to assign a public IP in awsvpcConfiguration.
    """

    # Required to be passed as command-line arguments
    cluster_arn: str
    execution_role_arn: str
    subnets: List[str]
    security_groups: List[str]
    # Set defaults for testing
    launch_type: Literal["EC2", "EXTERNAL", "FARGATE"] = "FARGATE"
    cpu: str = "256"
    memory: str = "512"
    family_prefix: str = "fail_on_purpose"
    region: str = "us-east-1"
    profile: str = "default"
    assign_public_ip: bool = True


def rand_suffix(n) -> str:
    """
    Generate a short random lowercase alphanumeric suffix.

    Parameters
    ----------
    n : int
        Length of the suffix.

    Returns
    -------
    str
        Random suffix.
    """
    alphabet: str = string.ascii_lowercase + string.digits
    return "".join(random.choice(alphabet) for _ in range(n))


def create_ecs_client(
    region: str,
    profile: str,
) -> ECSClient:
    """
    Create an ECS client.

    Parameters
    ----------
    region : str
        AWS region.
    profile : str
        AWS profile name.

    Returns
    -------
    ECSClient
        Boto3 ECS client.
    """
    client_config: Config = Config(
        region_name=region, retries={"max_attempts": 10, "mode": "standard"}
    )
    session = boto3.session.Session(region_name=region, profile_name=profile)
    return session.client(service_name="ecs", config=client_config)


def register_failing_taskdef(ecs_client: ECSClient, config: ECSConfig) -> str:
    """
    Register a task definition that cannot start due to a bad image tag.

    Parameters
    ----------
    ecs_client : ECSClient
        ECS client.
    config : ECSConfig
        Configuration parameters.

    Returns
    -------
    str
        Task definition ARN for the new revision.
    """
    family: str = f"{config.family_prefix}_{rand_suffix(n=6)}"
    task_def: Dict[str, Any] = {
        "family": family,
        "networkMode": "awsvpc",
        "requiresCompatibilities": [config.launch_type],
        "cpu": config.cpu,
        "memory": config.memory,
        "executionRoleArn": config.execution_role_arn,
        "containerDefinitions": [
            {
                "name": "bad_container",
                "image": "public.ecr.aws/amazonlinux/amazonlinux:this-tag-does-not-exist",
                "essential": True,
                "command": ["sh", "-c", "This should never run"],
                "readonlyRootFilesystem": True,
            }
        ],
    }

    response: RegisterTaskDefinitionResponseTypeDef = (
        ecs_client.register_task_definition(**task_def)
    )
    task_def_arn: str = response["taskDefinition"]["taskDefinitionArn"]
    logger.info(f"Registered task definition: {task_def_arn}")
    return task_def_arn


def run_task(ecs_client: ECSClient, config: ECSConfig, task_def_arn: str) -> str:
    """
    Run one task and return its ARN.

    Parameters
    ----------
    ecs_client : ECSClient
        ECS client.
    config : ECSConfig
        Configuration.
    task_def_arn : str
        Task definition to run.

    Returns
    -------
    str
        Task ARN.
    """
    run_resp: RunTaskResponseTypeDef = ecs_client.run_task(
        cluster=config.cluster_arn,
        taskDefinition=task_def_arn,
        count=1,
        launchType=config.launch_type,
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": config.subnets,
                "securityGroups": config.security_groups,
                "assignPublicIp": "ENABLED" if config.assign_public_ip else "DISABLED",
            }
        },
    )
    failures: List[FailureTypeDef] = run_resp.get("failures", [])
    if failures:
        raise RuntimeError(f"run_task failures: {failures}")

    task_arn: str = run_resp["tasks"][0]["taskArn"]
    logger.info(f"Started task: {task_arn}")
    return task_arn


def wait_for_stopped_and_describe(
    ecs_client: ECSClient, config: ECSConfig, task_arn: str, max_poll_seconds: int = 60
) -> TaskTypeDef:
    """
    Wait until the task is STOPPED, then poll DescribeTasks until stopCode appears.

    Parameters
    ----------
    ecs_client : ECSClient
        ECS client.
    config : ECSConfig
        Configuration.
    task_arn : str
        Task ARN to wait on.
    max_poll_seconds : int
        Total seconds to poll for stopCode after STOPPED.

    Returns
    -------
    TaskTypeDef
        Full task description.
    """
    waiter: TasksStoppedWaiter = ecs_client.get_waiter("tasks_stopped")
    # Default waiter polls every ~ 6 seconds up to 100 checks
    # https://boto3.amazonaws.com/v1/documentation/api/1.27.1/reference/services/ecs/waiter/TasksStopped.html
    waiter.wait(cluster=config.cluster_arn, tasks=[task_arn])

    # After STOPPED, ensure stopCode is present before proceeding
    deadline: float = time.time() + max_poll_seconds
    last_task: Optional[TaskTypeDef] = None
    desc: DescribeTasksResponseTypeDef
    tasks: List[TaskTypeDef]
    stop_code: Optional[str]
    while time.time() < deadline:
        logger.info(f"Polling for stopCode in DescribeTasks {time.strftime('%X')}")
        desc = ecs_client.describe_tasks(cluster=config.cluster_arn, tasks=[task_arn])
        tasks = desc.get("tasks", [])
        if tasks:
            last_task = tasks[0]
            stop_code = last_task.get("stopCode")
            if stop_code:
                return last_task
        time.sleep(5)

    # Return the last seen description even if stopCode was missing
    if last_task is None:
        raise RuntimeError("Task not found in `describe_tasks` after STOPPED")
    return last_task


def cleanup_task_definition(
    ecs_client: ECSClient, task_def_arn: Optional[str]
) -> Tuple[
    Optional[DeregisterTaskDefinitionResponseTypeDef],
    Optional[DeleteTaskDefinitionsResponseTypeDef],
]:
    """
    Deregister and delete the task definition revision.

    Parameters
    ----------
    ecs_client : ECSClient
        ECS client.
    task_def_arn : Optional[str]
        Task definition ARN to clean up.

    Returns
    -------
    Tuple[Optional[DeregisterTaskDefinitionResponseTypeDef], Optional[DeleteTaskDefinitionsResponseTypeDef]]
        Responses from deregister and delete calls.
    """
    if not task_def_arn:
        return None, None

    dereg_resp: DeregisterTaskDefinitionResponseTypeDef = (
        ecs_client.deregister_task_definition(taskDefinition=task_def_arn)
    )
    logger.info("Deregistered task definition: %s", task_def_arn)

    # Delete requires the revision to be INACTIVE
    del_resp: DeleteTaskDefinitionsResponseTypeDef = ecs_client.delete_task_definitions(
        taskDefinitions=[task_def_arn]
    )
    logger.info("Deleted task definition: %s", task_def_arn)
    return dereg_resp, del_resp


def parse_args(argv: Optional[List[str]] = None) -> ECSConfig:
    """
    Parse CLI arguments.

    Parameters
    ----------
    argv : Optional[List[str]]
        CLI args.

    Returns
    -------
    ECSConfig
        Parsed configuration.
    """
    parser = argparse.ArgumentParser(
        description="Run an ECS task that fails on purpose to test EventBridge rules"
    )
    parser.add_argument(
        "--cluster_arn", required=True, help="ECS cluster ARN to run the task on"
    )
    parser.add_argument(
        "--execution_role_arn", required=True, help="ecsTaskExecutionRole ARN"
    )
    parser.add_argument(
        "--subnets", nargs="+", required=True, help="Subnet IDs for awsvpc networking"
    )
    parser.add_argument(
        "--security-groups",
        nargs="+",
        required=True,
        help="Security group IDs for awsvpc networking",
    )
    parser.add_argument("--region", default="us-east-1", help="AWS region override")
    parser.add_argument("--profile", default="default", help="AWS profile override")

    args, _ = parser.parse_known_args(argv)

    return ECSConfig(
        cluster_arn=args.cluster_arn,
        execution_role_arn=args.execution_role_arn,
        subnets=args.subnets,
        security_groups=args.security_groups,
        region=args.region,
        profile=args.profile,
    )


def main(argv: Optional[List[str]] = None) -> int:
    config: ECSConfig = parse_args(argv)
    ecs_client: ECSClient = create_ecs_client(
        region=config.region, profile=config.profile
    )

    task_def_arn: Optional[str] = None
    try:
        task_def_arn = register_failing_taskdef(ecs_client=ecs_client, config=config)
        task_arn: str = run_task(
            ecs_client=ecs_client, config=config, task_def_arn=task_def_arn
        )
        task: TaskTypeDef = wait_for_stopped_and_describe(
            ecs_client, config, task_arn, max_poll_seconds=60
        )

        if task.get("stopCode") != "TaskFailedToStart":
            logger.error('Unexpected stopCode. Expected "TaskFailedToStart"')
            return 2
        return 0

    except (BotoCoreError, ClientError, Exception) as boto3_error:
        logger.error(f"Error occurred: {boto3_error}")
        return 1

    finally:
        try:
            cleanup_task_definition(ecs_client, task_def_arn)
        except Exception as cleanup_error:
            logger.warning(f"Cleanup failed: {cleanup_error}")


if __name__ == "__main__":
    sys.exit(main())
