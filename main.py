import os
from concurrent.futures import (
    Future,
    ProcessPoolExecutor,
)
from concurrent.futures import (
    TimeoutError as FutureTimeout,
)
from datetime import datetime

import pandas as pd

from src.api import query_etf_data
from src.utils import exit_on_error, setup_logger, write_to_s3

logger = setup_logger(name="ETF KPIs Scraper")


@exit_on_error(logger=logger)
def main() -> int:
    ENV = os.getenv("ENV", "dev")
    logger.info(f"Running the task in {ENV} mode")

    # If in 'dev' mode, specify a smaller number of etfs to query for testing purposes and a shorter timeout
    if ENV == "dev":
        max_etfs = 20
        timeout_seconds = 60 * 5
    elif ENV == "prod":
        max_etfs = int(os.getenv("MAX_ETFS", "1"))
        timeout_seconds = 60 * 45
    ipo_date = datetime.strptime(
        os.getenv("IPO_DATE", datetime.today().strftime("%Y-%m-%d")), "%Y-%m-%d"
    )

    logger.info(f"Submitting ETF query task (timeout {timeout_seconds}s)…")
    # Run query_etf_data in a separate process to enforce hard timeout
    with ProcessPoolExecutor(max_workers=1) as executor:
        future: Future[pd.DataFrame] = executor.submit(
            query_etf_data, logger, max_etfs, ipo_date
        )
        try:
            etfs_data = future.result(timeout=timeout_seconds)
        except FutureTimeout:
            logger.error(f"[ERROR] ETF query exceeded {timeout_seconds}s")
            # Raise to be caught by decorator
            raise

        s3_bucket = os.getenv("S3_BUCKET")
        if not s3_bucket:
            logger.error("[ERROR] S3_BUCKET environment variable is not set")
            raise RuntimeError("The S3_BUCKET environment variable is required")

        parquet = os.getenv("PARQUET") == "True"
        s3_path = f"s3://{s3_bucket}/daily-kpis/etf_kpis_{datetime.today().strftime('%Y_%m_%d')}"
        logger.info("Writing scraper data to s3")
        write_to_s3(data=etfs_data, s3_path=s3_path, parquet=parquet)
        logger.info(f"[SUCCESS] Successfully written data to s3")

        return 0


if __name__ == "__main__":
    main()
