from fastapi import APIRouter, HTTPException
import requests
import os
from pathlib import Path
from dotenv import load_dotenv
from datetime import datetime, timedelta
import yfinance as yf

load_dotenv(dotenv_path=Path(__file__).resolve().parents[2] / ".env")

router = APIRouter(prefix="/news", tags=["news"])

NEWS_API_KEY = os.getenv("NEWS_API_KEY", "")

# BIST30 sembol → şirket adı eşleşmesi (NewsAPI araması için)
SYMBOL_NAMES = {
    "THYAO": "Türk Hava Yolları THY",
    "ASELS": "Aselsan",
    "GARAN": "Garanti BBVA",
    "AKBNK": "Akbank",
    "SISE": "Şişecam",
    "EREGL": "Ereğli Demir Çelik",
    "KCHOL": "Koç Holding",
    "SASA": "Sasa Polyester",
    "HEKTS": "Hektaş",
    "PETKM": "Petkim",
    "FROTO": "Ford Otosan",
    "ISCTR": "İş Bankası",
    "AYGAZ": "Aygaz",
    "MGROS": "Migros",
    "SOKM": "Şok Market",
    "TCELL": "Turkcell",
    "TUPRS": "Tüpraş",
    "YKBNK": "Yapı Kredi",
    "TTKOM": "Türk Telekom",
    "ULKER": "Ülker Bisküvi",
    "BIMAS": "BİM Mağazalar",
    "ENKAI": "Enka İnşaat",
    "HALKB": "Halkbank",
    "VAKBN": "Vakıfbank",
}


@router.get("/bist30")
def get_bist30_news():
    if not NEWS_API_KEY:
        raise HTTPException(status_code=500, detail="NEWS_API_KEY ortam değişkeni ayarlanmamış")

    url = "https://newsapi.org/v2/everything"
    # Sadece borsa/piyasa/yatırım odaklı haberler
    params = {
        "q": (
            "BIST30 OR BİST30 OR \"borsa İstanbul\" OR \"hisse senedi\" OR "
            "\"BIST 100\" OR \"Borsa İstanbul\" OR THYAO OR GARAN OR AKBNK OR "
            "\"faiz kararı\" OR \"merkez bankası\" OR \"piyasalar\" OR \"endeks\""
        ),
        "language": "tr",
        "sortBy": "publishedAt",
        "pageSize": 40,
        "apiKey": NEWS_API_KEY,
    }

    # Alakasız anahtar kelimeler — bu kelimeleri içeren haberleri filtrele
    BLACKLIST = [
        "öğretmen", "cinayet", "okul", "müdür", "eğitim",
        "trafik", "deprem", "futbol", "spor", "magazin",
        "siyaset", "seçim", "mahkeme", "dava", "tutuklama",
    ]

    try:
        response = requests.get(url, params=params, timeout=10)
        data = response.json()

        if data.get("status") != "ok":
            raise HTTPException(status_code=502, detail=data.get("message", "NewsAPI hatası"))

        articles = []
        for a in data.get("articles", []):
            title = a.get("title") or ""
            description = a.get("description") or ""

            if title == "[Removed]":
                continue

            # Kara listedeki kelimelerden herhangi birini içeriyorsa atla
            combined = (title + " " + description).lower()
            if any(kw in combined for kw in BLACKLIST):
                continue

            articles.append({
                "title": title,
                "description": description,
                "url": a.get("url") or "",
                "source": (a.get("source") or {}).get("name") or "",
                "published_at": (a.get("publishedAt") or "")[:19].replace("T", " "),
                "image_url": a.get("urlToImage") or "",
            })

        return articles

    except requests.RequestException as e:
        raise HTTPException(status_code=502, detail=f"NewsAPI isteği başarısız: {e}")


@router.get("/stock/{symbol}")
def get_stock_news(symbol: str):
    if not NEWS_API_KEY:
        raise HTTPException(status_code=500, detail="NEWS_API_KEY ortam değişkeni ayarlanmamış")

    symbol = symbol.upper()
    company = SYMBOL_NAMES.get(symbol, symbol)

    url = "https://newsapi.org/v2/everything"
    params = {
        "q": f"{symbol} OR \"{company}\"",
        "language": "tr",
        "sortBy": "publishedAt",
        "pageSize": 15,
        "apiKey": NEWS_API_KEY,
    }

    try:
        response = requests.get(url, params=params, timeout=10)
        data = response.json()

        if data.get("status") != "ok":
            raise HTTPException(status_code=502, detail=data.get("message", "NewsAPI hatası"))

        # Hissenin son 3 aylık fiyat geçmişini çek
        yahoo_symbol = f"{symbol}.IS"
        try:
            stock = yf.Ticker(yahoo_symbol)
            hist = stock.history(period="3mo")
            # Tarih → {kapanış fiyatı, günlük değişim %} sözlüğü oluştur
            price_by_date = {}
            closes = list(hist["Close"])
            dates = [str(d)[:10] for d in hist.index]
            for i, date_str in enumerate(dates):
                prev = closes[i - 1] if i > 0 else closes[i]
                curr = closes[i]
                change_pct = ((curr - prev) / prev) * 100 if prev else 0.0
                price_by_date[date_str] = {
                    "close": float(curr),
                    "change_pct": round(float(change_pct), 2),
                }
        except Exception:
            price_by_date = {}

        articles = []
        for a in data.get("articles", []):
            title = a.get("title") or ""
            if title == "[Removed]":
                continue

            pub_date = (a.get("publishedAt") or "")[:10]

            # Haberin yayın tarihine en yakın işlem gününü bul
            price_impact = price_by_date.get(pub_date)
            if not price_impact:
                for delta in [1, -1, 2, -2, 3]:
                    try:
                        alt = (datetime.strptime(pub_date, "%Y-%m-%d") + timedelta(days=delta)).strftime("%Y-%m-%d")
                        if alt in price_by_date:
                            price_impact = price_by_date[alt]
                            break
                    except Exception:
                        pass

            articles.append({
                "title": title,
                "description": a.get("description") or "",
                "url": a.get("url") or "",
                "source": (a.get("source") or {}).get("name") or "",
                "published_at": (a.get("publishedAt") or "")[:19].replace("T", " "),
                "image_url": a.get("urlToImage") or "",
                "price_change_pct": price_impact["change_pct"] if price_impact else None,
                "price_close": price_impact["close"] if price_impact else None,
            })

        return articles

    except requests.RequestException as e:
        raise HTTPException(status_code=502, detail=f"NewsAPI isteği başarısız: {e}")
