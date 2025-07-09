# src/medila_integration_simulation/client_simulator.py
import requests
import json
import os
from dotenv import load_dotenv

# Načtení .env pro případné API URL z proměnných prostředí, pokud není lokální
load_dotenv()

# URL API endpointu - předpokládáme lokálně běžící API, pokud není specifikováno jinak
API_BASE_URL = os.getenv("STAPRO_API_URL", "http://localhost:8000")
INTERPRET_ENDPOINT_URL = f"{API_BASE_URL}/interpret"
HEALTH_ENDPOINT_URL = f"{API_BASE_URL}/health"

# --- Definice ukázkových JSON payloadů ---

payload_nehrazeny_abnormita_crp = {
  "request_id": "SIM_REQ_001_CRP_HIGH",
  "evaluation_method": "NEHRAZENY_POPIS_ABNORMITA", # Aktivace popisu jen při abnormitě
  "patient_metadata": {
    "gender": "muz",
    "age": 45
  },
  "current_lab_results": [
    {
      "parameter_code": "01001", # Kód pro CRP
      "parameter_name": "S_CRP",
      "value": "35.0",
      "unit": "mg/L",
      "reference_range_raw": "<5",
      "interpretation_status": "HIGH",
      "raw_dasta_skala": "| | ||"
    },
    {
      "parameter_code": "GLUC",
      "parameter_name": "S_Glukóza",
      "value": "5.1",
      "unit": "mmol/L",
      "reference_range_raw": "3.9-5.6",
      "interpretation_status": "NORMAL"
    }
  ],
  "dasta_text_sections": {
    "doctor_description": "Pacient si stěžuje na horečku a bolest v krku.",
    "memo_to_request": None
  },
  "diagnoses": ["Probíhající respirační infekt?"],
  "anamnesis_and_medication": {
    "anamnesis_text": "OA: Zdráv. FA: Žádná pravidelná medikace.",
    "medication_text": None
  }
}

payload_nehrazeny_vse_normal = {
  "request_id": "SIM_REQ_002_ALL_NORMAL",
  "evaluation_method": "NEHRAZENY_POPIS_NORMAL", # Popis se nemá generovat (mimo výjimek)
  "patient_metadata": {
    "gender": "žena",
    "age": 30
  },
  "current_lab_results": [
    {
      "parameter_code": "CHOL",
      "parameter_name": "S_Cholesterol",
      "value": "4.5",
      "unit": "mmol/L",
      "reference_range_raw": "<5.2",
      "interpretation_status": "NORMAL"
    },
    {
      "parameter_code": "ALT",
      "parameter_name": "S_ALT",
      "value": "0.4",
      "unit": "ukat/L",
      "reference_range_raw": "<0.58",
      "interpretation_status": "NORMAL"
    }
  ],
  "dasta_text_sections": {}, "diagnoses": [], "anamnesis_and_medication": {}
}

payload_vyjimka_psa_normal = {
  "request_id": "SIM_REQ_003_PSA_NORMAL",
  "evaluation_method": "NEHRAZENY_POPIS_PSA", # PSA se popisuje vždy
  "patient_metadata": {
    "gender": "muz",
    "age": 62
  },
  "current_lab_results": [
    {
      "parameter_code": "PSA01", # Kód pro PSA
      "parameter_name": "S_PSA celkový",
      "value": "3.1",
      "unit": "ug/L",
      "reference_range_raw": "Věkově specifické, např. <4.5", # Toto by mělo být přesnější
      "interpretation_status": "NORMAL" # I když je v normě, má se popsat
    }
  ],
  "dasta_text_sections": {}, "diagnoses": [], "anamnesis_and_medication": {}
}

payload_hrazeny_individualni_b1 = {
  "request_id": "SIM_REQ_004_HRAZ_B1",
  "evaluation_method": "HRAZENY_POPIS_INDIVIDUALNI", # B1
  "patient_metadata": {
    "gender": "žena",
    "age": 58,
    "historical_data_access_key": "patient_history_token_b1"
  },
  "current_lab_results": [
    {
      "parameter_code": "TSH", "parameter_name": "S_TSH", "value": "6.5", "unit": "mIU/L",
      "reference_range_raw": "0.27-4.2", "interpretation_status": "HIGH"
    },
    {
      "parameter_code": "FT4", "parameter_name": "S_FT4", "value": "12.0", "unit": "pmol/L",
      "reference_range_raw": "12-22", "interpretation_status": "NORMAL"
    },
    { # Přidáno pro demonstraci popisu normální hodnoty
      "parameter_code": "VITD", "parameter_name": "S_Vitamin D (25-OH)", "value": "75", "unit": "nmol/L",
      "reference_range_raw": "50-250", "interpretation_status": "NORMAL"
    }
  ],
  "dasta_text_sections": {"doctor_description": "Kontrola štítné žlázy, pacientka udává únavu a zimomřivost."},
  "diagnoses": ["Hypothyreosis subclinica susp."],
  "anamnesis_and_medication": {"anamnesis_text": "Rodinná anamnéza onemocnění štítné žlázy."}
}

payload_hrazeny_balicek_b2 = {
  "request_id": "SIM_REQ_005_HRAZ_B2",
  "evaluation_method": "HRAZENY_POPIS_BALICEK_PREVENCE_MUZ", # B2
  "patient_metadata": {
    "gender": "muz",
    "age": 50,
    "historical_data_access_key": "patient_history_token_b2"
  },
  "current_lab_results": [
    {"parameter_code": "GLUC", "parameter_name": "S_Glukóza", "value": "5.8", "unit": "mmol/L", "reference_range_raw": "3.9-5.6", "interpretation_status": "HIGH"},
    {"parameter_code": "CHOLT", "parameter_name": "S_Cholesterol celkový", "value": "6.1", "unit": "mmol/L", "reference_range_raw": "<5.2", "interpretation_status": "HIGH"},
    {"parameter_code": "HDLCH", "parameter_name": "S_HDL Cholesterol", "value": "1.1", "unit": "mmol/L", "reference_range_raw": ">1.0", "interpretation_status": "NORMAL"},
    {"parameter_code": "LDLCH", "parameter_name": "S_LDL Cholesterol", "value": "4.0", "unit": "mmol/L", "reference_range_raw": "<3.0", "interpretation_status": "HIGH"},
    {"parameter_code": "TRIG", "parameter_name": "S_Triacylglyceroly", "value": "2.1", "unit": "mmol/L", "reference_range_raw": "<1.7", "interpretation_status": "HIGH"},
    {"parameter_code": "KOCRB", "parameter_name": "B_Erytrocyty (KO)", "value": "4.9", "unit": "10^12/L", "reference_range_raw": "4.2-5.4", "interpretation_status": "NORMAL"},
    {"parameter_code": "PSA01", "parameter_name": "S_PSA celkový", "value": "1.5", "unit": "ug/L", "reference_range_raw": "<4.0", "interpretation_status": "NORMAL"}
  ],
  "dasta_text_sections": {"doctor_description": "Preventivní prohlídka v 50 letech."},
  "diagnoses": ["Mírná arteriální hypertenze"],
  "anamnesis_and_medication": {"anamnesis_text": "Kuřák 10 cig/den. Otec IM v 60 letech.", "medication_text": "Agen 5mg"}
}

payloads_to_test = [
    payload_nehrazeny_abnormita_crp,
    payload_nehrazeny_vse_normal,
    payload_vyjimka_psa_normal,
    payload_hrazeny_individualni_b1,
    payload_hrazeny_balicek_b2
]

def call_interpret_api(payload: dict) -> dict:
    """
    Odešle požadavek na /interpret endpoint a vrátí odpověď jako slovník.
    """
    print(f"\n--- Volání API pro Request ID: {payload.get('request_id', 'N/A')} ---")
    print(f"Evaluation method: {payload.get('evaluation_method')}")
    print(f"Odesílaná data (část): {json.dumps(payload, indent=2, ensure_ascii=False)[:500]}...")

    try:
        response = requests.post(INTERPRET_ENDPOINT_URL, json=payload, timeout=120) # Timeout 120s pro LLM
        response.raise_for_status() # Vyvolá HTTPError pro chybové status kódy (4xx, 5xx)

        response_data = response.json()
        print("\nOdpověď z API (JSON):")
        print(json.dumps(response_data, indent=2, ensure_ascii=False))
        return response_data

    except requests.exceptions.HTTPError as http_err:
        print(f"HTTP chyba: {http_err}")
        try:
            error_detail = response.json()
            print(f"Detail chyby z API: {json.dumps(error_detail, indent=2, ensure_ascii=False)}")
            return {"error_type": "HTTPError", "status_code": response.status_code, "detail": error_detail}
        except json.JSONDecodeError:
            print(f"Detail chyby z API (raw text): {response.text}")
            return {"error_type": "HTTPError", "status_code": response.status_code, "raw_text_detail": response.text}

    except requests.exceptions.RequestException as req_err:
        print(f"Chyba spojení nebo požadavku: {req_err}")
        return {"error_type": "RequestException", "message": str(req_err)}
    except Exception as e:
        print(f"Neočekávaná chyba při volání API: {e}")
        return {"error_type": "Unknown", "message": str(e)}

def simulate_medila_processing(api_response: dict):
    """
    Simuluje, jak by Medila (OpenLIMS) mohla zpracovat odpověď z API.
    """
    print("\n--- Simulace zpracování v Medile ---")
    if "error_type" in api_response or api_response.get("error"):
        print("API vrátilo chybu, interpretace nebude vložena.")
        print(f"Detail chyby pro Medilu: {api_response}")
        # Zde by Medila logovala chybu, případně upozornila uživatele
    elif api_response.get("interpretation_text"):
        interpretation_text = api_response["interpretation_text"]
        request_id = api_response.get("request_id", "N/A")
        print(f"Pro žádanku ID: {request_id}, byla přijata interpretace:")
        print("----------------------------------------------------")
        print(interpretation_text)
        print("----------------------------------------------------")
        print("Tato interpretace by se nyní vložila do bloku 'ME-PopisyNaVL' v Medile.")
        # Zde by následovala logika pro uložení textu do příslušného bloku v OpenLIMS.
        # Např. aktualizace databáze, zobrazení v UI pro editaci lékařem atd.
    else:
        print("API nevrátilo očekávaný formát interpretace.")
        print(f"Přijatá data: {api_response}")

def check_api_health():
    print("\n--- Kontrola stavu API (/health) ---")
    try:
        response = requests.get(HEALTH_ENDPOINT_URL, timeout=10)
        response.raise_for_status()
        print(f"Stav API: {response.status_code}")
        print(f"Odpověď: {response.json()}")
        return True
    except requests.exceptions.RequestException as e:
        print(f"Chyba při kontrole stavu API: {e}")
        return False

if __name__ == "__main__":
    print("Simulátor klientských volání pro STAPRO AI Interpretace API")

    # Nejprve zkontrolujeme stav API
    if not check_api_health():
        print("\nAPI není dostupné. Ukončuji simulaci.")
        print(f"Ujistěte se, že FastAPI server běží na {API_BASE_URL}")
        exit()

    for i, payload_example in enumerate(payloads_to_test):
        print(f"\n\n===== Testovací scénář {i+1} =====")
        api_result = call_interpret_api(payload_example)
        simulate_medila_processing(api_result)

        if i < len(payloads_to_test) - 1:
            # Malá pauza mezi voláními, aby se předešlo zahlcení (pokud by LLM byl pomalý)
            # import time
            # time.sleep(2)
            pass

    print("\n\n===== Simulace dokončena =====")

    # Poznámka pro uživatele:
    # Pro spuštění tohoto skriptu:
    # 1. Ujistěte se, že máte nastavené proměnné prostředí v .env souboru
    #    (zejména pro Azure OpenAI a Azure AI Search, pokud je RAG plně integrován).
    # 2. Spusťte FastAPI server: uvicorn src.api.main:app --reload --host 0.0.0.0 --port 8000
    # 3. Spusťte tento skript: python -m src.medila_integration_simulation.client_simulator
    #    (nebo python src/medila_integration_simulation/client_simulator.py pokud je src v PYTHONPATH)
