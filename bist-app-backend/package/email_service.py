"""Gmail SMTP ile alarm bildirimi gönderir."""
import smtplib
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from pathlib import Path

# Proje kökündeki .env dosyasını yükle
try:
    from dotenv import load_dotenv
    _env_path = Path(__file__).resolve().parents[2] / ".env"
    load_dotenv(_env_path)
except ImportError:
    pass

# .env veya ortam değişkenlerinden oku
GMAIL_USER = os.getenv("GMAIL_USER", "")        # örn: senin@gmail.com
GMAIL_APP_PASSWORD = os.getenv("GMAIL_APP_PASSWORD", "")  # Google App Password


def send_alarm_email(
    to_email: str,
    symbol: str,
    current_price: float,
    bound_type: str,        # "alt" veya "üst"
    bound_value: float,
    user_name: str = "",
) -> bool:
    """Fiyat alarmı tetiklendiğinde kullanıcıya mail atar. True → başarılı."""
    if not GMAIL_USER or not GMAIL_APP_PASSWORD:
        print("⚠️  GMAIL_USER veya GMAIL_APP_PASSWORD ayarlanmamış — mail atılamadı.")
        return False

    direction = "yükseldi ▲" if bound_type == "üst" else "düştü ▼"
    subject = f"🔔 {symbol} fiyat alarmı tetiklendi!"

    html = f"""
    <html><body style="font-family:Arial,sans-serif;background:#f4f4f4;padding:20px;">
      <div style="max-width:480px;margin:auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.1);">
        <div style="background:#10B981;padding:24px;text-align:center;">
          <h1 style="color:#fff;margin:0;font-size:22px;">🔔 Fiyat Alarmı</h1>
        </div>
        <div style="padding:24px;">
          <p style="font-size:16px;">Merhaba{' ' + user_name if user_name else ''},</p>
          <p style="font-size:15px;">
            <strong>{symbol}</strong> hissesi için belirlediğin
            <strong>{bound_type} sınır</strong> ({bound_value:.2f} ₺) aşıldı.
          </p>
          <div style="background:#f0fdf4;border:1px solid #10B981;border-radius:8px;padding:16px;text-align:center;margin:16px 0;">
            <div style="font-size:13px;color:#6b7280;">Güncel Fiyat</div>
            <div style="font-size:28px;font-weight:bold;color:#10B981;">₺{current_price:.2f}</div>
            <div style="font-size:14px;color:#374151;">{symbol} {direction}</div>
          </div>
          <p style="font-size:13px;color:#6b7280;">Bu alarm artık pasif hale getirildi.</p>
        </div>
        <div style="background:#f9fafb;padding:16px;text-align:center;font-size:12px;color:#9ca3af;">
          BIST30 Takip Uygulaması
        </div>
      </div>
    </body></html>
    """

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = GMAIL_USER
    msg["To"] = to_email
    msg.attach(MIMEText(html, "html", "utf-8"))

    try:
        with smtplib.SMTP_SSL("smtp.gmail.com", 465, timeout=10) as server:
            server.login(GMAIL_USER, GMAIL_APP_PASSWORD)
            server.sendmail(GMAIL_USER, to_email, msg.as_string())
        print(f"✅ Alarm maili gönderildi → {to_email} ({symbol} @ {current_price})")
        return True
    except Exception as e:
        print(f"❌ Mail gönderme hatası: {e}")
        return False
