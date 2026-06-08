"""Her 5 dakikada bir aktif alarmları kontrol eder, tetiklenince mail atar."""
import asyncio
import time
import requests
from datetime import datetime

from .db import SessionLocal
from . import models
from .email_service import send_alarm_email
from .routers.market import _get_yahoo_session, BIST30_SYMBOLS

CHECK_INTERVAL = 300  # saniye (5 dakika)


def _fetch_prices() -> dict[str, float]:
    """BIST30 anlık fiyatlarını çek. {symbol: price}"""
    session = _get_yahoo_session()
    headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}
    prices: dict[str, float] = {}
    for symbol in BIST30_SYMBOLS:
        try:
            r = session.get(
                f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}.IS?interval=1d&range=1d",
                headers=headers,
                timeout=8,
            )
            if r.status_code == 200:
                meta = r.json()["chart"]["result"][0]["meta"]
                price = float(meta.get("regularMarketPrice") or 0)
                if price > 0:
                    prices[symbol] = price
        except Exception as e:
            print(f"Fiyat çekme hatası {symbol}: {e}")
    return prices


def check_alarms_once():
    """Tüm aktif alarmları kontrol et, tetiklenenler için mail at."""
    db = SessionLocal()
    try:
        alarms = (
            db.query(models.Alarm)
            .filter(models.Alarm.is_triggered == False)  # noqa: E712
            .all()
        )
        if not alarms:
            return

        prices = _fetch_prices()
        if not prices:
            print("⚠️  Fiyat verisi alınamadı, alarm kontrolü atlandı.")
            return

        for alarm in alarms:
            price = prices.get(alarm.symbol)
            if price is None:
                continue

            triggered = False
            bound_type = ""
            bound_value = 0.0

            if alarm.upper_bound is not None and price >= alarm.upper_bound:
                triggered = True
                bound_type = "üst"
                bound_value = alarm.upper_bound

            elif alarm.lower_bound is not None and price <= alarm.lower_bound:
                triggered = True
                bound_type = "alt"
                bound_value = alarm.lower_bound

            if triggered:
                user = db.query(models.User).filter(models.User.id == alarm.user_id).first()
                if user:
                    send_alarm_email(
                        to_email=user.email,
                        symbol=alarm.symbol,
                        current_price=price,
                        bound_type=bound_type,
                        bound_value=bound_value,
                        user_name=user.first_name or "",
                    )
                alarm.is_triggered = True
                alarm.triggered_at = datetime.utcnow()
                db.commit()
                print(f"🔔 Alarm tetiklendi: {alarm.symbol} @ {price} ({bound_type} sınır: {bound_value})")

    except Exception as e:
        print(f"Alarm kontrol hatası: {e}")
    finally:
        db.close()


async def alarm_scheduler_loop():
    """FastAPI lifespan içinde çalışan sonsuz döngü."""
    print("⏰ Alarm scheduler başlatıldı (5 dk aralık)")
    while True:
        try:
            check_alarms_once()
        except Exception as e:
            print(f"Scheduler hatası: {e}")
        await asyncio.sleep(CHECK_INTERVAL)
