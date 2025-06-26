# Použijeme oficiální Python image.
# Zvolíme specifickou verzi pro reprodukovatelnost, např. Python 3.11
FROM python:3.11-slim

# Nastavení pracovního adresáře v kontejneru
WORKDIR /app

# Instalace systémových závislostí, pokud by byly potřeba (např. pro některé knihovny)
# RUN apt-get update && apt-get install -y --no-install-recommends <potřebné-balíčky> && rm -rf /var/lib/apt/lists/*

# Kopírování souboru se závislostmi a instalace závislostí
# Nejprve kopírujeme jen requirements.txt, abychom využili Docker layer caching.
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Kopírování celého adresáře src (s naší aplikací) do kontejneru
COPY ./src ./src

# Nastavení proměnné prostředí PYTHONPATH, aby Python našel naše moduly v src/
ENV PYTHONPATH=/app

# Port, na kterém bude FastAPI aplikace naslouchat uvnitř kontejneru
EXPOSE 8000

# Příkaz pro spuštění Uvicorn serveru
# Budeme naslouchat na 0.0.0.0, aby byla aplikace dostupná zvenčí kontejneru.
# --host 0.0.0.0 je důležité pro běh v kontejneru.
# src.api.main:app odkazuje na modul src/api/main.py a v něm na instanci FastAPI s názvem 'app'.
CMD ["uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
