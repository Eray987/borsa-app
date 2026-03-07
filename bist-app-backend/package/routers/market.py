from fastapi import APIRouter, Depends, HTTPException
import yfinance as yf

router = APIRouter(prefix="/market", tags=["market"])

BIST30_SYMBOLS = [
    "THYAO.IS", "ASELS.IS", "GARAN.IS", "AKBNK.IS", "SISE.IS",
    "EREGL.IS", "KCHOL.IS", "SASA.IS", "HEKTS.IS", "PETKM.IS",
    "FROTO.IS", "KLDMB.IS", "ISCTR.IS", "AYGAZ.IS", "MGROS.IS",
    "SOKM.IS", "TCELL.IS", "TUPRS.IS", "YKBNK.IS", "TTKOM.IS",
    "ULKER.IS", "BIMAS.IS", "COHOL.IS", "ODEA.IS", "HALKB.IS",
    "VAKBN.IS", "ENKAI.IS", "ANHOL.IS", " Kardemir.IS", "CLTLY.IS"
]

@router.get("/bist30")
def get_bist30():
    stocks_data = []
    for symbol in BIST30_SYMBOLS:
        try:
            stock = yf.Ticker(symbol)
            info = stock.info
            
            price = info.get('currentPrice') or info.get('regularMarketPreviousClose')
            change = info.get('regularMarketChangePercent')
            name = info.get('shortName') or info.get('longName', symbol)
            
            if price:
                stocks_data.append({
                    "symbol": symbol.replace(".IS", ""),
                    "name": name,
                    "price": price,
                    "change_percent": change or 0.0
                })
        except Exception as e:
            print(f"Error fetching {symbol}: {e}")
            continue
    
    return stocks_data


@router.get("/stock/{symbol}")
def get_stock_detail(symbol: str, period: str = "1mo"):
    yahoo_symbol = f"{symbol}.IS"
    
    try:
        stock = yf.Ticker(yahoo_symbol)
        info = stock.info
        
        current_price = info.get('currentPrice') or info.get('regularMarketPreviousClose')
        change = info.get('regularMarketChangePercent') or 0.0
        name = info.get('shortName') or info.get('longName', symbol)
        
        hist = stock.history(period=period)
        
        chart_data = []
        for date, row in hist.iterrows():
            chart_data.append({
                "date": str(date)[:10],
                "close": float(row['Close'])
            })
        
        return {
            "symbol": symbol,
            "name": name,
            "price": current_price,
            "change_percent": change,
            "chart": chart_data
        }
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Hisse bulunamadı: {str(e)}")
