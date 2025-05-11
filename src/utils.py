import logging
import sys
from collections.abc import Callable
from functools import wraps
from typing import Any, Dict, List, NoReturn, Optional, ParamSpec, TypeVar, overload

import awswrangler as wr
import pandas as pd

P = ParamSpec("P")  # Captures the parameter types of a callable
R = TypeVar("R")  # Represents the return type of a callable


@overload
def exit_on_error(decorated_function: Callable[P, R]) -> Callable[P, R]: ...


@overload
def exit_on_error(
    *, logger: logging.Logger
) -> Callable[[Callable[P, R]], Callable[P, R]]: ...


def exit_on_error(
    decorated_function: Any = None,
    *,
    logger: Optional[logging.Logger] = None,
) -> Any:
    """
    Decorator that wraps a function so that any uncaught exception
    is logged and the process exits with status code 1. On normal
    completion, exits with status code 0.

    Parameters
    ----------
    decorated_function : Optional[Callable[P, R]]
        The function to wrap when decorator is used without args.
    logger : Optional[logging.Logger]
        An explicit Logger instance to use; if None, a new one is created per function.

    Returns
    -------
    Callable[P, NoReturn]
        The decorated function that runs `func` and exits interpreter.
    """

    def decorator(decorated_function: Callable[P, R]) -> Callable[P, NoReturn]:
        # Use provided logger or create one based on function name
        logger = logger or setup_logger(decorated_function.__name__)

        @wraps(decorated_function)
        def safe_wrapper(*args: P.args, **kwargs: P.kwargs) -> NoReturn:
            try:
                decorated_function(*args, **kwargs)
                sys.exit(0)
            except Exception:
                logger.exception("[ERROR] Unhandled exception error occurred")
                sys.exit(1)

        return safe_wrapper

    # If decorator used without parentheses
    if decorated_function is not None and callable(decorated_function):
        return decorator(decorated_function)
    return decorator


def setup_logger(name: str) -> logging.Logger:
    """
    Set up a logger with the specified name. If a handler is already attached, it won't add another.

    Parameters
    ----------
    name : str
        The name of the logger

    Returns
    -------
    logging.Logger
        A logger instance
    """
    logger = logging.getLogger(name)  # Return a logger with the specified name

    if not logger.hasHandlers():
        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    logger.setLevel(logging.INFO)

    return logger


def write_to_s3(
    data: pd.DataFrame, s3_path: str, parquet: bool = True
) -> Dict[str, List[str]]:
    """
    Save the input data to s3 either as a parquet file or csv file.

    Parameters
    ----------
    data : pd.DataFrame
        Data Frame to be saved
    s3_path : str
        Full s3 url, excluding the file extension
    parquet : bool, optional
        `True` for parquet or `False` for csv

    Returns
    -------
    Dict[str, List[str]]
        A dictionary containing list of all store objects paths
    """
    if parquet:
        paths = wr.s3.to_parquet(df=data, path=f"{s3_path}.parquet")
    else:
        paths = wr.s3.to_csv(df=data, path=f"{s3_path}.csv")
    return paths  # type: ignore
