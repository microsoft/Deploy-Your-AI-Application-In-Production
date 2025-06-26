# tools/medila_api_client_simulator.py

import requests
import json
import os
from dotenv import load_dotenv

# Načtení .env pro případné konfigurace, i když zde primárně cílíme na URL API
# Pokud by API vyžadovalo klíč, načítali bychom ho odtud.
dotenv_path = os.path.join(os.path.dirname(__file__), "..", ".env")
if os.path.exists(dotenv_path):
    load_dotenv(dotenv_path)
else:
    load_dotenv()

# URL našeho lokálně běžícího API (nebo nasazeného API, pokud bychom testovali proti němu)
STAPRO_API_BASE_URL = os.getenv("STAPRO_API_URL", "http://localhost:8000")
INTERPRET_ENDPOINT_URL = f"{STAPRO_API_BASE_URL}/interpret"
HEALTH_ENDPOINT_URL = f"{STAPRO_API_BASE_URL}/health"


def check_api_health():
    """Ověří stav API pomocí /health endpointu."""
    print(f"--- Ověřování stavu API na: {HEALTH_ENDPOINT_URL} ---")
    try:
        response = requests.get(HEALTH_ENDPOINT_URL, timeout=5)
        response.raise_for_status() # Vyvolá chybu pro HTTP kódy 4xx/5xx
        health_data = response.json()
        print(f"Stav API: {health_data.get('status', 'Neznámý')}, Zpráva: {health_data.get('message', 'Žádná')}")
        return True
    except requests.exceptions.RequestException as e:
        print(f"CHYBA: API není dostupné nebo neodpovídá správně na {HEALTH_ENDPOINT_URL}.")
        print(f"Detail chyby: {e}")
        return False
    except json.JSONDecodeError:
        print(f"CHYBA: Odpověď z /health endpointu není validní JSON.")
        print(f"Raw odpověď: {response.text}")
        return False


def simulate_interpretation_request(payload: dict):
    """
    Simuluje odeslání požadavku na interpretaci laboratorních výsledků.
    """
    if not isinstance(payload, dict):
        print("CHYBA: Payload musí být slovník (dict).")
        return

    request_id = payload.get("request_id", "Neznámé ID")
    print(f"\n--- Simulace požadavku na interpretaci pro request_id: {request_id} ---")
    print(f"Odesílání na: {INTERPRET_ENDPOINT_URL}")
    # print(f"Payload:\n{json.dumps(payload, indent=2, ensure_ascii=False)}")

    try:
        response = requests.post(INTERPRET_ENDPOINT_URL, json=payload, timeout=60) # Timeout 60s pro LLM
        response.raise_for_status() # Vyvolá chybu pro HTTP kódy 4xx/5xx

        response_data = response.json()
        print("\nOdpověď z API (HTTP Status Code {}):".format(response.status_code))
        print(json.dumps(response_data, indent=2, ensure_ascii=False))

        if response_data.get("interpretation_text"):
            print("\n--- Vygenerovaná interpretace ---")
            print(response_data["interpretation_text"])
            print("--- Konec interpretace ---")
        elif response_data.get("error"):
            print(f"\nAPI vrátilo chybu: {response_data['error']}")

    except requests.exceptions.HTTPError as http_err:
        print(f"CHYBA HTTP při volání API: {http_err}")
        try:
            error_detail = http_err.response.json()
            print(f"Detail chyby z API: {json.dumps(error_detail, indent=2, ensure_ascii=False)}")
        except json.JSONDecodeError:
            print(f"Raw chybová odpověď z API: {http_err.response.text}")
    except requests.exceptions.ConnectionError as conn_err:
        print(f"CHYBA PŘIPOJENÍ: Nepodařilo se připojit k API na {INTERPRET_ENDPOINT_URL}.")
        print("Ujistěte se, že FastAPI server běží (např. `uvicorn src.api.main:app --reload`).")
        print(f"Detail chyby: {conn_err}")
    except requests.exceptions.Timeout:
        print(f"CHYBA TIMEOUT: Požadavek na API překročil časový limit.")
    except Exception as err:
        print(f"CHYBA: Neočekávaná chyba při simulaci požadavku: {err}")


if __name__ == "__main__":
    print(">>> Simulátor Klienta Medila API <<<")

    if not check_api_health():
        print("\nAPI server se zdá být nedostupný. Ukončuji simulátor.")
        exit()

    # --- Ukázkové payloady ---

    payload_1_nehrazeny_abnormita = {
      "request_id": "SIM_NEHR_ABN_001",
      "evaluation_method": "NEHRAZENY_POPIS_ABNORMITA_CRP_GLUC", # Upřesnění pro testování
      "patient_metadata": {"gender": "muz", "age": 55},
      "current_lab_results": [
        {"parameter_code": "01001", "parameter_name": "S_CRP", "value": "25.0", "unit": "mg/L", "reference_range_raw": "<5", "interpretation_status": "HIGH"},
        {"parameter_code": "GLUC", "parameter_name": "S_Glukóza", "value": "7.5", "unit": "mmol/L", "reference_range_raw": "3.9-5.6", "interpretation_status": "HIGH"}
      ],
      "dasta_text_sections": {"doctor_description": "Pacient si stěžuje na únavu a žízeň."},
      "diagnoses": ["Hypertenze"],
      "anamnesis_and_medication": {"anamnesis_text": "Rodinná anamnéza diabetu.", "medication_text": " antihypertenziva"}
    }

    payload_2_nehrazeny_normal = {
      "request_id": "SIM_NEHR_NORM_002",
      "evaluation_method": "NEHRAZENY_POPIS_NORMAL_CHOL",
      "patient_metadata": {"gender": "žena", "age": 40},
      "current_lab_results": [
        {"parameter_code": "CHOL", "parameter_name": "S_Cholesterol", "value": "4.8", "unit": "mmol/L", "reference_range_raw": "<5.2", "interpretation_status": "NORMAL"}
      ],
      "dasta_text_sections": {}, "diagnoses": [], "anamnesis_and_medication": {}
    }

    payload_3_vyjimka_psa = {
      "request_id": "SIM_VYJIMKA_PSA_003",
      "evaluation_method": "NEHRAZENY_POPIS_PSA_VYJIMKA", # evaluation_method může obsahovat info o typu
      "patient_metadata": {"gender": "muz", "age": 67, "historical_data_access_key": "patient_PSA_hist"},
      "current_lab_results": [
        {"parameter_code": "01631", "parameter_name": "S_PSA celk.", "value": "4.1", "unit": "ug/L", "reference_range_raw": "VĚK SPECIF.", "interpretation_status": "BORDERLINE"}
        # Pro PSA je důležité, aby AI zohlednila věk, i když je hodnota "v normě" pro obecnou populaci
      ],
      "dasta_text_sections": {"doctor_description": "Preventivní prohlídka."},
      "diagnoses": ["Benigní hyperplazie prostaty v anamnéze"],
      "anamnesis_and_medication": {}
    }

    payload_4_hrazeny_balicek = {
      "request_id": "SIM_HRAZ_BAL_004",
      "evaluation_method": "HRAZENY_POPIS_BALICEK_KOMPLET",
      "patient_metadata": { "gender": "žena", "age": 32, "historical_data_access_key": "patient_hist_004"},
      "current_lab_results": [
        {"parameter_code": "01001","parameter_name": "S_CRP","value": "1.2","unit": "mg/L","reference_range_raw": "<5","interpretation_status": "NORMAL"},
        {"parameter_code": "TSH","parameter_name": "S_TSH","value": "5.8","unit": "mIU/L","reference_range_raw": "0.27-4.2","interpretation_status": "HIGH"},
        {"parameter_code": "FT4","parameter_name": "S_volný T4","value": "12.5","unit": "pmol/L","reference_range_raw": "12-22","interpretation_status": "NORMAL"},
        {"parameter_code": "FERR", "parameter_name": "S_Feritin", "value": "10", "unit": "ug/L", "reference_range_raw": "13-150", "interpretation_status": "LOW"}
      ],
      "dasta_text_sections": {"doctor_description": "Únava, vypadávání vlasů."},
      "diagnoses": ["Anémie z nedostatku železa - suspektní"],
      "anamnesis_and_medication": {"anamnesis_text": "Vegetariánka."}
    }

    # Spuštění simulací
    simulate_interpretation_request(payload_1_nehrazeny_abnormita)
    simulate_interpretation_request(payload_2_nehrazeny_normal)
    simulate_interpretation_request(payload_3_vyjimka_psa)
    simulate_interpretation_request(payload_4_hrazeny_balicek)

    print("\n>>> Simulace dokončena <<<")
