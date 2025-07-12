import os
import sys
from datetime import datetime
from typing import Optional

import pandas as pd

from src.api import query_etf_and_stock_data
from src.utils import catch_errors, setup_logger, write_to_s3


@catch_errors
def main() -> int:
    logger = setup_logger(name="ETF KPIs Scraper")
    logger.info("Starting ETF KPIs scraper")
    ENV: str = os.getenv("ENV", "dev")
    logger.info(f"Running the task in {ENV} mode")

    market_data: pd.DataFrame = query_etf_and_stock_data(logger=logger, env=ENV)
    if market_data.isna().to_numpy().all():
        logger.error("[ERROR] Market data is completely filled with missing values")
        return 1

    s3_bucket: Optional[str] = os.getenv("S3_BUCKET")
    if not s3_bucket:
        logger.error("[ERROR] The S3_BUCKET environment variable is not set")
        return 1
    parquet: bool = os.getenv("PARQUET") == "True"
    s3_path: str = (
        f"s3://{s3_bucket}/daily-kpis/etf_kpis_{datetime.today().strftime('%Y_%m_%d')}"
    )
    logger.info("Writing scraper data to s3")
    write_to_s3(data=market_data, s3_path=s3_path, parquet=parquet)
    logger.info(f"[SUCCESS] Successfully written data to s3")

    return 0


if __name__ == "__main__":
    sys.exit(main())
