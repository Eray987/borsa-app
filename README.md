# borsa-app

backend çalıştırma: 
cd bist-app-backend
source /Users/eray/Desktop/Borsa/.venv/bin/activate
pip install -r ../requirements.txt
python -m uvicorn package.main:app --host 0.0.0.0 --port 8000 --reload

mobil uygulama çalıştırma: 
cd bist_mobile_app
flutter run

android adb hatası alırsan:
- Android SDK ve platform-tools kurulu olmalı
- ANDROID_HOME / ANDROID_SDK_ROOT doğru ayarlı olmalı
- gerekirse Android Studio > SDK Manager içinden platform-tools yükle
- emülatör yerine iPhone Simulator kullanacaksan `flutter devices` ile cihazı seçip `flutter run -d <device_id>` çalıştır

dataset toplama:
cd bist-app-backend
python3 scripts/collect_market_dataset.py --period 10y --output data/raw/bist_ohlcv_10y.csv

training dataset oluşturma:
python3 scripts/build_training_dataset.py --input data/raw/bist_ohlcv_10y.csv --output data/processed/bist_training_dataset.csv

model eğitimi:
python3 scripts/train_model.py --input data/processed/bist_training_dataset.csv --model-dir saved_models