import os
from datetime import datetime
from logging import Logger
from pathlib import Path
from random import choices
from typing import Dict, List, Union

import pandas as pd
import requests
import yfinance as yf

apikey = os.getenv("API_KEY")
url = f"https://www.alphavantage.co/query?function=TOP_GAINERS_LOSERS&apikey={apikey}"
pd.set_option("mode.copy_on_write", True)
etf_tickers = [
    "SPY",
    "VOO",
    "VTI",
    "QTEC",
    "QQQM",
    "IYW",
    "VGT",
    "SMH",
    "SOXX",
    "PSI",
    "XSD",
]

# Set the cache location for yfinance
default_cache_location = Path.cwd() / ".cache" / "py-yfinance"
default_cache_location.mkdir(parents=True, exist_ok=True)
yf.set_tz_cache_location(default_cache_location)

skippable_http_status_codes = {404, 408}


def query_etf_and_stock_data(logger: Logger, env: str) -> pd.DataFrame:
    """
    Query ETFs and top 20 biggest gainer stock data from the Alpha Vantage API and Yahoo Finance API.

    Parameters
    ----------
    logger : Logger
        Logger instance to log information
    env : str
        Environment variable to determine how many requests to make

    Returns
    -------
    pd.DataFrame
        DataFrame containing ETF and stock data
    """
    if not apikey:
        logger.error("[ERROR] API_KEY environment variable is not set")
        raise ValueError("API_KEY environment variable is required")

    logger.info("Making request to Alpha Vantage API for top gainers data")
    response: requests.Response = requests.get(url)
    if response.status_code != 200:
        logger.error(f"Request to {url} failed with status code {response.status_code}")
        raise requests.exceptions.RequestException(
            f"Request to {url} failed with status code {response.status_code}"
        )
    response_data: Dict[str, Union[str, List[Dict[str, str]]]] = response.json()
    top_gainers: pd.DataFrame = pd.DataFrame(response_data["top_gainers"])
    top_gainers_tickers: List[str] = top_gainers["ticker"].to_list()
    gains: Dict[str, str] = dict(
        zip(top_gainers["ticker"], top_gainers["change_percentage"])
    )

    logger.info(
        "Top 20 Gainer Stocks:\n"
        + "\n".join([f"   {ticker: <8} {pct: >10}" for ticker, pct in gains.items()])
    )
    if env == "prod":
        tickers = yf.Tickers(tickers=top_gainers_tickers + etf_tickers)
    else:
        tickers = yf.Tickers(
            tickers=choices(population=etf_tickers, k=3)
            + choices(population=top_gainers_tickers, k=3)
        )

    logger.info(
        f"Sending GET requests to Yahoo Finance for data on {len(tickers.tickers)} tickers (ETFs and stocks)"
    )
    yf_data = []
    for ticker in tickers.tickers.values():
        try:
            info = ticker.info or {}
        except requests.exceptions.HTTPError as http_error:
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
                "first_trade_date": info.get("firstTradeDateMilliseconds", pd.NA),
                "business_summary": info.get("longBusinessSummary", pd.NA),
                "previous_close": info.get("previousClose", pd.NA),
                "nav_price": info.get("navPrice", pd.NA),
                "dividend_yield": info.get("dividendYield", pd.NA),
                "net_expense_ratio": info.get("netExpenseRatio", pd.NA),
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
    logger.info("Completed requesting data from Yahoo Finance, creating DataFrame")
    data = pd.DataFrame(yf_data).dropna(how="all", axis=0)

    logger.info("Converting first_trade_date to datetime format and adding date column")
    data["first_trade_date"] = pd.to_datetime(
        data["first_trade_date"], unit="ms", errors="coerce"
    )
    data["date"] = datetime.today().strftime("%Y-%m-%d")

    logger.info("Mapping data types")
    data = data.astype(
        {
            "symbol": pd.StringDtype(),
            "date": "datetime64[ns]",
            "first_trade_date": "datetime64[ns]",
            "previous_close": pd.Float64Dtype(),
            "nav_price": pd.Float64Dtype(),
            "dividend_yield": pd.Float64Dtype(),
            "net_expense_ratio": pd.Float64Dtype(),
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
