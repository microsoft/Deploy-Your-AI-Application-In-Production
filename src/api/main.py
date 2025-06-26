# src/api/main.py
import json
from fastapi import FastAPI, HTTPException, Body
from pydantic import BaseModel, Field, Json
from typing import Dict, Any, Union

# Importujeme logiku AI enginu
# Předpokládáme, že repozitář je strukturován tak, aby tento import fungoval.
# Možná bude potřeba upravit PYTHONPATH nebo strukturu projektu, pokud by nastal problém s importem.
# Pro jednoduchost předpokládám, že `src` je v PYTHONPATHu nebo FastAPI spouštíme z kořene projektu.
try:
    from src.ai_engine.main import get_lab_interpretation
except ImportError:
    # Fallback pro případ, že by import selhal (např. při testování mimo plný kontext projektu)
    # Toto by se v produkci nemělo dít, pokud je projekt správně strukturován.
    print("WARN: Nepodařilo se importovat 'get_lab_interpretation' z 'src.ai_engine.main'. Používám mock funkci.")
    def get_lab_interpretation(raw_json_input_string: str) -> str:
        return json.dumps({"mock_interpretation": "Toto je mockovaná odpověď, AI engine nebyl správně načten.", "input": raw_json_input_string})

# Pydantic modely pro vstup a výstup API

class InterpretationRequest(BaseModel):
    # Očekáváme, že tělo POST požadavku bude přímo JSON string,
    # jak je specifikováno ("OpenLIMS bude ... odesílat jeden JSON objekt jako stringový atribut v těle HTTP požadavku")
    # FastAPI však typicky parsuje JSON tělo automaticky do Pydantic modelu.
    # Abychom přijali raw JSON string v těle, můžeme použít `Body(..., media_type="application/json")`
    # nebo jednodušeji definovat model, který očekává tento string.
    # Problém je, že specifikace říká "jeden JSON objekt jako stringový atribut v těle HTTP požadavku".
    # To je trochu nejednoznačné. Pokud by to znamenalo {"json_payload": "stringified_json_here"},
    # pak by model byl: json_payload: str.
    # Pokud to znamená, že celé tělo je ten stringified JSON, pak je to složitější s FastAPI,
    # které by se ho snažilo parsovat.
    # Prozatím předpokládám, že OpenLIMS pošle JSON objekt, který FastAPI zparsuje do slovníku.
    # A my tento slovník převedeme zpět na JSON string pro náš AI engine, který očekává string.
    # Toto je potřeba vyjasnit!
    #
    # AKTUALIZACE PO ÚVAZE: Zadání říká:
    # "OpenLIMS bude pro každé volání AI sestavovat a odesílat jeden JSON objekt jako stringový atribut v těle HTTP požadavku."
    # To zní, jako by tělo POST bylo např.: {"request_data_as_string": "{ \"request_id\": \"...\", ... }"}
    # Nebo, že celé tělo je ten string, ale pak by Content-Type měl být text/plain nebo application/octet-stream,
    # a FastAPI by ho muselo číst manuálně.
    #
    # Zvolím kompromis: API bude očekávat standardní JSON tělo (FastAPI ho zparsuje).
    # Pokud OpenLIMS posílá string v atributu, bude to např. {"data": "escapovaný JSON string"}
    # Pokud OpenLIMS posílá přímo JSON objekt, je to ideální.
    # Náš `get_lab_interpretation` očekává JSON string, takže data z požadavku převedeme na string.

    # Pro jednoduchost nyní budeme očekávat přímo ten JSON objekt, který pak převedeme na string.
    # FastAPI defaultně očekává `application/json` a parsuje ho.
    # Pokud by OpenLIMS posílalo `Content-Type: text/plain` s JSON stringem, museli bychom to řešit jinak.
    # Původní specifikace JSON vstupu pro AI engine:
    # {
    #   "request_id": "GUID_unikatni_identifikator_zadanky",
    #   "evaluation_method": "NEHRAZENY_POPIS_PSA",
    #   "patient_metadata": { ... },
    #   "current_lab_results": [ ... ],
    #   ...
    # }
    # Toto bude tělo požadavku.
    request_id: str = Field(..., examples=["GUID_unikatni_identifikator_zadanky"])
    evaluation_method: str = Field(..., examples=["NEHRAZENY_POPIS_PSA"])
    patient_metadata: Dict[str, Any] = Field(default_factory=dict)
    current_lab_results: list[Dict[str, Any]] = Field(default_factory=list)
    dasta_text_sections: Optional[Dict[str, Any]] = Field(default_factory=dict)
    diagnoses: Optional[list[str]] = Field(default_factory=list)
    anamnesis_and_medication: Optional[Dict[str, Any]] = Field(default_factory=dict)

    # Přidáme metodu pro konverzi na JSON string, který očekává AI engine
    def to_engine_input_string(self) -> str:
        return self.model_dump_json()


class InterpretationResponse(BaseModel):
    request_id: str = Field(examples=["GUID_unikatni_identifikator_zadanky"])
    interpretation_text: Optional[str] = None
    error: Optional[str] = None
    # Můžeme přidat další metadata, např. verze modelu, timestamp z AI enginu, pokud je poskytne

# Inicializace FastAPI aplikace
app = FastAPI(
    title="STAPRO AI Laboratorní Interpretace API",
    version="0.1.0",
    description="API pro automatickou interpretaci laboratorních výsledků pomocí AI."
)

@app.post("/interpret", response_model=InterpretationResponse, tags=["Interpretace"])
async def interpret_lab_results(request_data: InterpretationRequest):
    """
    Přijme laboratorní data ve formátu JSON a vrátí textovou interpretaci.

    - **request_id**: Unikátní ID žádanky pro sledování.
    - **evaluation_method**: Určuje typ interpretace/metodu AI agenta.
    - **patient_metadata**: Metadata o pacientovi (pohlaví, věk, atd.).
    - **current_lab_results**: Aktuální laboratorní výsledky.
    - **dasta_text_sections**: Textové sekce z DASTA.
    - **diagnoses**: Diagnózy z RES bloku.
    - **anamnesis_and_medication**: Anamnéza a medikace.
    """
    input_json_string = request_data.to_engine_input_string()

    # Volání AI enginu
    ai_response_str = get_lab_interpretation(input_json_string)

    try:
        # AI engine může vrátit buď přímo text interpretace (úspěch)
        # nebo JSON string s chybou.
        ai_response_data = json.loads(ai_response_str)

        if "error" in ai_response_data:
            # Chyba z AI enginu
            # Logování chyby by zde bylo vhodné
            print(f"API: Chyba z AI enginu: {ai_response_data.get('error')}, Detail: {ai_response_data.get('detail')}")
            raise HTTPException(
                status_code=ai_response_data.get("status_code", 500),
                detail=ai_response_data.get("error", "Neznámá chyba v AI enginu")
            )

        # Pokud AI engine vrátí JSON, který není chyba, ale obsahuje interpretaci
        # (dle původní specifikace výstupu AI enginu)
        # { "request_id": "...", "interpretation_text": "..." }
        # To by znamenalo, že get_lab_interpretation vrací JSON string i v úspěšném případě.
        # Aktuálně je navržen tak, že vrací přímo text interpretace.
        # Pokud by se to změnilo, musela by se tato část upravit.
        # Prozatím předpokládáme, že pokud to není JSON s 'error', je to text.
        # Tento scénář by nastal, pokud by get_lab_interpretation vracel JSON i pro úspěch.
        # Pro jednoduchost nyní předpokládám, že pokud je to validní JSON a nemá 'error',
        # tak je to struktura { "request_id": "...", "interpretation_text": "..." }
        # Ale náš `get_lab_interpretation` vrací přímo string interpretace.
        # Takže tato větev se pravděpodobně neuplatní, pokud `ai_response_str` není chyba.

        # Tento blok by se uplatnil, pokud by AI engine vracel strukturovaný JSON i pro úspěch:
        # return InterpretationResponse(
        #     request_id=ai_response_data.get("request_id", request_data.request_id),
        #     interpretation_text=ai_response_data.get("interpretation_text")
        # )
        # Jelikož get_lab_interpretation vrací přímo string interpretace (pokud není chyba),
        # tak tento případ nenastane. Chyba json.loads() nastane, pokud je to čistý text.

    except json.JSONDecodeError:
        # Předpokládáme, že `ai_response_str` je přímo text interpretace (úspěšný případ)
        return InterpretationResponse(
            request_id=request_data.request_id,
            interpretation_text=ai_response_str
        )
    except HTTPException:
        raise # Znovu vyvoláme HTTPException, aby ji FastAPI zpracovalo
    except Exception as e:
        # Jakákoliv jiná neočekávaná chyba
        print(f"API: Neočekávaná chyba při zpracování odpovědi z AI enginu: {e}")
        raise HTTPException(status_code=500, detail="Interní chyba serveru při zpracování AI odpovědi.")


@app.get("/health", tags=["Stav"])
async def health_check():
    """Jednoduchý endpoint pro ověření stavu API."""
    return {"status": "ok", "message": "STAPRO AI Interpretation API je funkční."}

# Pro spuštění FastAPI aplikace lokálně (např. pro testování):
# Použijte příkaz: uvicorn src.api.main:app --reload
# (Spusťte z kořenového adresáře projektu)

if __name__ == "__main__":
    # Tento blok se typicky nepoužívá pro FastAPI, spouští se přes uvicorn.
    # Ale pro rychlý test můžeme:
    # import uvicorn
    # uvicorn.run(app, host="0.0.0.0", port=8000)
    print("FastAPI aplikace definována. Spusťte pomocí Uvicorn, např.:")
    print("uvicorn src.api.main:app --reload --host 0.0.0.0 --port 8000")

    # Příklad, jak by OpenLIMS mohlo volat API (pomocí `requests`):
    """
    import requests
    import json

    api_url = "http://localhost:8000/interpret"

    payload = {
      "request_id": "GUID_API_TEST_002",
      "evaluation_method": "NEHRAZENY_POPIS_NORMAL",
      "patient_metadata": {
        "gender": "žena",
        "age": 28
      },
      "current_lab_results": [
        {
          "parameter_code": "CRP",
          "parameter_name": "S_CRP",
          "value": "1.5",
          "unit": "mg/L",
          "reference_range_raw": "<5",
          "interpretation_status": "NORMAL"
        }
      ]
    }

    try:
        response = requests.post(api_url, json=payload)
        response.raise_for_status() # Vyvolá chybu pro HTTP kódy 4xx/5xx

        response_data = response.json()
        print("Odpověď z API:")
        print(json.dumps(response_data, indent=2, ensure_ascii=False))

    except requests.exceptions.HTTPError as http_err:
        print(f"HTTP chyba: {http_err}")
        try:
            print(f"Detail chyby z API: {response.json()}")
        except json.JSONDecodeError:
            print(f"Detail chyby z API (raw): {response.text}")
    except Exception as err:
        print(f"Jiná chyba: {err}")
    """
    pass
