import os
from datetime import datetime
from logging import Logger
from pathlib import Path

import numpy as np
import pandas as pd
import yfinance as yf
from curl_cffi.requests.exceptions import HTTPError

apikey = os.getenv("API_KEY")
csv_url = f"https://www.alphavantage.co/query?function=LISTING_STATUS&state=active&apikey={apikey}"
pd.set_option("mode.copy_on_write", True)
random_state = np.random.RandomState(12)

# Set the cache location for yfinance
default_cache_location = Path.cwd() / ".cache" / "py-yfinance"
default_cache_location.mkdir(parents=True, exist_ok=True)
yf.set_tz_cache_location(default_cache_location)

skippable_http_status_codes = {404, 408}


def query_etf_data(logger: Logger, max_etfs: int, ipo_date: datetime) -> pd.DataFrame:
    """
    Query ETFs from the Alpha Vantage API and Yahoo Finance API.

    Parameters
    ----------
    logger : Logger
        Logger instance to log information
    max_etfs : int
        Maximum number of ETFs to query, to avoid hitting the rate limit
    ipo_date : datetime
        Keep ETFs that were IPOed after this date

    Returns
    -------
    pd.DataFrame
        DataFrame containing ETF data
    """
    logger.info("Making request to endpoint, which uses CSV format")
    etf_data = pd.read_csv(csv_url)
    etf_data = etf_data.rename(
        columns={"assetType": "asset_type", "ipoDate": "ipo_date"}
    )
    # Filter for ETFs on NASDAQ and NYSE
    etf_data = etf_data.loc[
        (etf_data["asset_type"] == "ETF")
        & (
            (etf_data["exchange"] == "NASDAQ")
            | (etf_data["exchange"].str.contains("NYSE"))
        )
    ]
    etf_data = etf_data[["symbol", "name", "ipo_date"]]
    etf_data["ipo_date"] = pd.to_datetime(etf_data["ipo_date"])
    etf_data = etf_data.loc[etf_data["ipo_date"] > ipo_date]
    if max_etfs < etf_data.shape[0]:
        etf_data = etf_data.sample(n=max_etfs, random_state=random_state)
    logger.info(
        f"Number of active ETFs on Nasdaq and NYSE as of {datetime.today().strftime('%Y-%m-%d')} with IPO date after {ipo_date.strftime('%Y-%m-%d')}: {etf_data.shape[0]}"
    )

    symbols = etf_data["symbol"].str.cat(sep=" ")
    tickers = yf.Tickers(tickers=symbols)

    logger.info(
        "Sending GET requests to yahoo finance for each ETF in the list of ETFs from Alpha Vantage"
    )
    yf_data = []
    for ticker in tickers.tickers.values():
        try:
            info = ticker.info or {}
        except HTTPError as http_error:
            if (
                response := http_error.response
            ) and response.status_code in skippable_http_status_codes:
                logger.warning(
                    f"HTTP {response.status_code} when attempting to access `info` for ticker {ticker.ticker!r}"
                )
                info = {}
            else:
                raise http_error
        except Exception as unexpected_error:
            # Catch anything else (parsing, attribute errors, etc.)
            logger.warning(
                f"Unexpected error for ticker {ticker.ticker!r}: {unexpected_error!r}"
            )
            info = {}

        yf_data.append(
            {
                "symbol": info.get("symbol", pd.NA),
                "business_summary": info.get("longBusinessSummary", pd.NA),
                "previous_close": info.get("previousClose", pd.NA),
                "nav_price": info.get("navPrice", pd.NA),
                "trailing_pe": info.get("trailingPE", pd.NA),
                "volume": info.get("volume", pd.NA),
                "average_volume": info.get("averageVolume", pd.NA),
                "bid": info.get("bid", pd.NA),
                "bid_size": info.get("bidSize", pd.NA),
                "ask_size": info.get("askSize", pd.NA),
                "ask": info.get("ask", pd.NA),
                "category": info.get("category", pd.NA),
                "beta_three_year": info.get("beta3Year", pd.NA),
                "ytd_return": info.get("ytdReturn", pd.NA),
                "three_year_avg_return": info.get("threeYearAverageReturn", pd.NA),
                "five_year_avg_return": info.get("fiveYearAverageReturn", pd.NA),
            }
        )
    logger.info(
        "Completed requesting data from yahoo finance, saving it as a data frame"
    )
    yf_data = pd.DataFrame(yf_data)

    logger.info(
        "Left joining performance data from yahoo finance data onto the etf data using 'symbol' as a key"
    )
    data = pd.merge(left=etf_data, right=yf_data, on="symbol", how="left")

    logger.info("Mapping data types")
    data = data.astype(
        {
            "symbol": pd.StringDtype(),
            "name": pd.StringDtype(),
            "ipo_date": "datetime64[ns]",
            "previous_close": pd.Float64Dtype(),
            "nav_price": pd.Float64Dtype(),
            "trailing_pe": pd.Float64Dtype(),
            "volume": pd.Float64Dtype(),
            "average_volume": pd.Float64Dtype(),
            "bid": pd.Float64Dtype(),
            "bid_size": pd.Float64Dtype(),
            "ask_size": pd.Float64Dtype(),
            "ask": pd.Float64Dtype(),
            "category": pd.StringDtype(),
            "beta_three_year": pd.Float64Dtype(),
            "ytd_return": pd.Float64Dtype(),
            "three_year_avg_return": pd.Float64Dtype(),
            "five_year_avg_return": pd.Float64Dtype(),
            "business_summary": pd.StringDtype(),
        }
    )

    return data
