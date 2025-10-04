import logging
import sys
from collections.abc import Callable
from functools import wraps
from typing import ParamSpec, TypeVar, Union

import awswrangler as wr
import pandas as pd

P = ParamSpec("P")  # Captures the parameter types of a callable
R = TypeVar("R")  # Represents the return type of a callable


def catch_errors(decorated_function: Callable[P, R]) -> Callable[P, Union[R, int]]:
    """
    Decorator that wraps a function to catch and log unhandled errors.

    Parameters
    ----------
    decorated_function: Callable[P, R]
        Function to wrap.

    Returns
    -------
    Callable[P, Union[R, int]]
        Wrapped function that returns the original function's return value
        or 1 if an exception occurs.
    """

    @wraps(wrapped=decorated_function)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> Union[R, int]:
        logger: logging.Logger = setup_logger(name=decorated_function.__name__)
        try:
            return decorated_function(*args, **kwargs)
        except Exception as unhandled_error:
            logger.error(
                f"[ERROR] Unhandled error occurred in {decorated_function.__name__}: {unhandled_error}",
                exc_info=True,
            )
            return 1

    return wrapper


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
    logger: logging.Logger = logging.getLogger(
        name
    )  # Return a logger with the specified name

    if not logger.hasHandlers():
        handler: logging.StreamHandler = logging.StreamHandler(sys.stdout)
        formatter: logging.Formatter = logging.Formatter(
            "%(asctime)s %(levelname)s %(name)s: %(message)s"
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    logger.setLevel(logging.INFO)

    return logger


def write_to_s3(data: pd.DataFrame, s3_path: str, parquet: bool = True) -> None:
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
    None
    """
    if parquet:
        wr.s3.to_parquet(df=data, path=f"{s3_path}.parquet")
    else:
        wr.s3.to_csv(df=data, path=f"{s3_path}.csv")
    return None
