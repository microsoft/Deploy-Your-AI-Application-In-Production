# src/ai_engine/tools/lab_data_normalizer.py
import json
from typing import Type, Dict, Any
from langchain_core.tools import BaseTool, tool
from pydantic import BaseModel, Field

class LabDataNormalizerInput(BaseModel):
    raw_json_data: str = Field(description="Surová laboratorní data ve formátu JSON string, jak byla přijata z OpenLIMS.")

@tool("lab_data_normalizer_tool", args_schema=LabDataNormalizerInput, return_direct=False)
def normalize_lab_data_func(raw_json_data: str) -> Dict[str, Any]:
    """
    Normalizuje a validuje surová laboratorní data z JSON vstupu.
    Převede vstupní JSON string do standardizovaného Python slovníku.
    V této fázi provádí základní parsování JSON.
    Rozšíření mohou zahrnovat detailnější validaci struktury, kontrolu typů,
    převod jednotek, doplnění referenčních rozsahů dle věku/pohlaví atd.
    """
    try:
        normalized_data = json.loads(raw_json_data)
    except json.JSONDecodeError as e:
        return {"error": f"Chyba při parsování JSON: {str(e)}", "original_data": raw_json_data}

    # Příklad jednoduché validace nebo transformace (lze rozšířit)
    if not isinstance(normalized_data, dict):
        return {"error": "Očekáván JSON objekt (slovník).", "parsed_data": normalized_data}

    # Můžeme přidat kontrolu povinných polí, pokud je to nutné
    # např. if "request_id" not in normalized_data:
    #           return {"error": "Chybí povinné pole 'request_id'.", "data": normalized_data}

    # Prozatím vrací parsovaná data; v budoucnu zde bude více logiky
    return normalized_data

# Alternativní způsob definice nástroje jako třídy, pokud preferujete OOP přístup
class LabDataNormalizerTool(BaseTool):
    name: str = "lab_data_normalizer_tool"
    description: str = (
        "Normalizuje a validuje surová laboratorní data z JSON vstupu. "
        "Převede vstupní JSON string do standardizovaného Python slovníku. "
        "Použij tento nástroj jako první krok pro zpracování vstupních dat z OpenLIMS."
    )
    args_schema: Type[BaseModel] = LabDataNormalizerInput
    return_direct: bool = False # Agent rozhodne, co dál

    def _run(self, raw_json_data: str) -> Dict[str, Any]:
        return normalize_lab_data_func(raw_json_data)

    async def _arun(self, raw_json_data: str) -> Dict[str, Any]:
        # Pro asynchronní operace, pokud by byly potřeba
        # V tomto případě můžeme volat synchronní verzi
        return self._run(raw_json_data)

if __name__ == '__main__':
    # Příklad použití
    sample_raw_json = """
    {
      "request_id": "GUID12345",
      "evaluation_method": "NEHRAZENY_POPIS_PSA",
      "patient_metadata": {
        "gender": "muz",
        "age": 45
      },
      "current_lab_results": [
        {
          "parameter_code": "01001",
          "parameter_name": "S_CRP",
          "value": "35.0",
          "unit": "mg/L",
          "reference_range_raw": "<5",
          "interpretation_status": "HIGH"
        }
      ]
    }
    """

    # Použití funkce přímo
    result_func = normalize_lab_data_func(sample_raw_json)
    print("Výsledek z funkce:", result_func)

    # Použití nástroje
    tool_instance = LabDataNormalizerTool()
    result_tool = tool_instance.invoke({"raw_json_data": sample_raw_json})
    print("Výsledek z nástroje:", result_tool)

    error_json = '{"key": "value", "unterminated_string: "test'
    result_error = normalize_lab_data_func(error_json)
    print("Výsledek chyby:", result_error)
