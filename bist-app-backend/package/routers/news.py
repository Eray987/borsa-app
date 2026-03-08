from fastapi import APIRouter, HTTPException
import requests
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(dotenv_path=Path(__file__).resolve().parents[2] / ".env")

router = APIRouter(prefix="/news", tags=["news"])

NEWS_API_KEY = os.getenv("NEWS_API_KEY", "")


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
