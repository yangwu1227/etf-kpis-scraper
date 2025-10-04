import logging
import os
from typing import Any, Dict, List, Literal, cast

import boto3
import botocore
from mypy_boto3_ecs import ECSClient
from mypy_boto3_ecs.type_defs import (
    ContainerOverrideTypeDef,
    NetworkConfigurationTypeDef,
    RunTaskResponseTypeDef,
)
from pydantic import BaseModel, ConfigDict

ecs_client: ECSClient = boto3.client("ecs")
logger: logging.Logger = logging.getLogger(name="Trigger ECS Fargate Task")
logger.setLevel(logging.INFO)
type ASSIGN_PUBLIC_IP_OPTIONS = Literal["ENABLED", "DISABLED"]


class EnvironmentConfig(BaseModel):
    """
    Environment configuration for the Lambda function.
    """

    cluster_name: str
    task_definition: str
    container_name: str
    subnet_1: str
    subnet_2: str
    security_group: str
    assign_public_ip: ASSIGN_PUBLIC_IP_OPTIONS
    env: str

    model_config = ConfigDict(
        frozen=True,
        validate_assignment=True,
        extra="forbid",
    )


def environment_config() -> EnvironmentConfig:
    """
    Load environment configuration from environment variables.

    Returns
    -------
    EnvironmentConfig
        Environment configuration model instance.
    """
    assign_public_ip: ASSIGN_PUBLIC_IP_OPTIONS = cast(
        ASSIGN_PUBLIC_IP_OPTIONS, os.getenv("ASSIGN_PUBLIC_IP", "DISABLED")
    )

    try:
        env_config: EnvironmentConfig = EnvironmentConfig(
            cluster_name=os.getenv("ECS_CLUSTER_NAME", ""),
            task_definition=os.getenv("ECS_TASK_DEFINITION", ""),
            container_name=os.getenv("ECS_CONTAINER_NAME", ""),
            subnet_1=os.getenv("SUBNET_1", ""),
            subnet_2=os.getenv("SUBNET_2", ""),
            security_group=os.getenv("SECURITY_GROUP", ""),
            assign_public_ip=assign_public_ip,
            env=os.getenv("env", "prod"),
        )
        empty_fields: List[str] = [
            field
            for field, value in env_config.model_dump().items()
            if field not in ["env", "assign_public_ip"] and not value
        ]
        if empty_fields:
            raise ValueError(
                f"Missing required environment variables: {', '.join(empty_fields)}"
            )
        return env_config
    except Exception as error:
        logger.error(
            f"An error occurred while loading the environment configuration: {error}"
        )
        raise


def lambda_handler(event: Dict[str, str], context: Any) -> None:
    try:
        env_config: EnvironmentConfig = environment_config()

        # If 'env' is passed in as part of the event payload, e.g. {"env": "dev"}, use that value
        env: str = event.get("env", env_config.env)

        # Get the latest revision of the task definition
        version: int = ecs_client.describe_task_definition(
            taskDefinition=env_config.task_definition
        )["taskDefinition"]["revision"]

        # Network configurations
        network_config: NetworkConfigurationTypeDef = {
            "awsvpcConfiguration": {
                "subnets": [env_config.subnet_1, env_config.subnet_2],
                "securityGroups": [env_config.security_group],
                "assignPublicIp": env_config.assign_public_ip,
            }
        }

        # Continer overrides
        container_override: ContainerOverrideTypeDef = {
            "name": env_config.container_name,
            "environment": [{"name": "ENV", "value": env}],
        }

        response: RunTaskResponseTypeDef = ecs_client.run_task(
            cluster=env_config.cluster_name,
            launchType="FARGATE",
            count=1,
            taskDefinition=f"{env_config.task_definition}:{version}",
            networkConfiguration=network_config,
            overrides={"containerOverrides": [container_override]},
        )

        logger.info(f"Task started with taskArn: {response}")

    except botocore.exceptions.ClientError as error:
        logger.error(f"An error occurred while starting the task: {error}")
        raise error

    except botocore.exceptions.ParamValidationError as error:
        logger.error(
            f"The parameters passed to the `run_task` method are invalid: {error}"
        )
        raise error

    except Exception as error:
        logger.error(f"An unknown error occurred: {error}")
        raise error

    return None
