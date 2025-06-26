# src/ai_engine/main.py
import json
from .core.chains import ai_engine_chain # Importujeme hlavní chain

def get_lab_interpretation(raw_json_input_string: str) -> str:
    """
    Hlavní funkce pro získání interpretace laboratorních výsledků.
    Přijímá surový JSON string a vrací textovou interpretaci.
    """
    if not isinstance(raw_json_input_string, str):
        return json.dumps({
            "error": "Vstup musí být JSON string.",
            "status_code": 400
        })

    try:
        # Ověření, zda je vstup validní JSON (i když normalizer to také dělá)
        json.loads(raw_json_input_string)
    except json.JSONDecodeError as e:
        return json.dumps({
            "error": f"Nevalidní JSON vstup: {str(e)}",
            "status_code": 400
        })

    try:
        # Spuštění hlavního LangChain řetězce
        # Vstup pro řetězec je slovník s klíčem 'raw_json_input'
        result_interpretation = ai_engine_chain.invoke({"raw_json_input": raw_json_input_string})
        return result_interpretation # Toto by měl být finální textový výstup od LLM
    except Exception as e:
        # Logování chyby by zde bylo vhodné v produkčním kódu
        print(f"Došlo k chybě v AI enginu: {e}") # Základní logování na konzoli
        # Vrátíme strukturovanou chybovou odpověď, kterou může API vrstva dále zpracovat
        # V produkci by se neměly vracet detailní interní chyby koncovému uživateli přímo.
        return json.dumps({
            "error": "Došlo k interní chybě při generování interpretace.",
            "detail": str(e), # Pro debug, v produkci opatrně
            "status_code": 500
        })

if __name__ == '__main__':
    # Příklad použití z příkazové řádky nebo pro jednoduché testování
    sample_input_json_string = """
    {
      "request_id": "GUID_MAIN_TEST_001",
      "evaluation_method": "NEHRAZENY_POPIS_ABNORMITA",
      "patient_metadata": {
        "gender": "muz",
        "age": 52
      },
      "current_lab_results": [
        {
          "parameter_code": "CHOL",
          "parameter_name": "S_Cholesterol",
          "value": "7.2",
          "unit": "mmol/L",
          "reference_range_raw": "<5.2",
          "interpretation_status": "HIGH"
        },
        {
          "parameter_code": "TRIG",
          "parameter_name": "S_Triacylglyceroly",
          "value": "2.5",
          "unit": "mmol/L",
          "reference_range_raw": "<1.7",
          "interpretation_status": "HIGH"
        }
      ],
      "dasta_text_sections": {},
      "diagnoses": ["Esenciální hypertenze"],
      "anamnesis_and_medication": {
        "anamnesis_text": "Kuřák, stres v práci.",
        "medication_text": "Concor COR"
      }
    }
    """
    print("--- Volání get_lab_interpretation ---")

    # Pro spuštění tohoto testu je potřeba mít nastavené proměnné prostředí pro Azure OpenAI
    # (AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY, AZURE_OPENAI_CHAT_DEPLOYMENT_NAME)
    # a také nainstalované potřebné knihovny.

    # Načtení .env, pokud existuje (pro lokální testování, pokud spouštíte tento soubor přímo)
    from dotenv import load_dotenv
    load_dotenv()

    interpretation = get_lab_interpretation(sample_input_json_string)

    print("\n--- Výsledná interpretace (z main.py) ---")
    # Výstup může být buď text interpretace nebo JSON s chybou
    try:
        # Zkusíme parsovat jako JSON, pokud je to chyba
        error_data = json.loads(interpretation)
        if "error" in error_data:
            print(json.dumps(error_data, indent=2, ensure_ascii=False))
        else: # Pokud to není JSON chyba, je to text interpretace
            print(interpretation)
    except json.JSONDecodeError:
        # Pokud to není validní JSON, je to přímo text interpretace
        print(interpretation)

    print("\n--- Test s nevalidním JSON vstupem ---")
    invalid_json = '{"key": "value", "unterminated_string: "test'
    error_interpretation = get_lab_interpretation(invalid_json)
    print(json.dumps(json.loads(error_interpretation), indent=2, ensure_ascii=False))

    print("\n--- Test s None vstupem ---")
    none_interpretation = get_lab_interpretation(None)
    print(json.dumps(json.loads(none_interpretation), indent=2, ensure_ascii=False))
