# src/ai_engine/tools/predictive_analysis.py
from typing import Type, Dict, Any, List
from langchain_core.tools import BaseTool, tool
from pydantic import BaseModel, Field

class PredictiveAnalysisInput(BaseModel):
    normalized_lab_data: Dict[str, Any] = Field(description="Normalizovaná a validovaná laboratorní data ve formátu Python slovníku, výstup z LabDataNormalizerTool.")
    # Mohou zde být další relevantní vstupy, např. patient_history_summary

@tool("predictive_analysis_tool", args_schema=PredictiveAnalysisInput, return_direct=False)
def run_predictive_analysis_func(normalized_lab_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Placeholder pro nástroj spouštějící prediktivní AI modely.
    V této fázi vrací pouze mockovaná (ukázková) data, protože skutečné
    prediktivní modely zatím nejsou implementovány ani specifikovány.
    Identifikuje potenciální patologické stavy, rizikové faktory nebo anomálie
    na základě kombinace parametrů v `normalized_lab_data`.
    """

    # Příklad: Extrakce relevantních hodnot pro "predikci"
    # Toto je velmi zjednodušené a pouze pro ilustraci
    identified_risks: List[str] = []
    potential_diagnoses: List[str] = []

    # Příklad jednoduché logiky na základě CRP (C-reaktivní protein)
    # Skutečná logika by byla mnohem komplexnější a založená na trénovaných modelech
    for result in normalized_lab_data.get("current_lab_results", []):
        param_name = result.get("parameter_name", "").lower()
        value_str = result.get("value", "")
        interpretation = result.get("interpretation_status", "").upper()

        if "crp" in param_name:
            try:
                value = float(value_str)
                if interpretation == "HIGH":
                    if value > 100:
                        identified_risks.append("Vysoké riziko závažné bakteriální infekce nebo rozsáhlého zánětu (na základě CRP).")
                        potential_diagnoses.append("Možná sepse / závažná infekce (na základě CRP).")
                    elif value > 10:
                        identified_risks.append("Zvýšené riziko zánětlivého onemocnění (na základě CRP).")
                        potential_diagnoses.append("Možný zánětlivý proces (na základě CRP).")
            except ValueError:
                # Hodnota není číslo, ignorovat pro tuto jednoduchou logiku
                pass

        # Příklad pro glukózu
        if "glukóza" in param_name or "glucose" in param_name:
            try:
                value = float(value_str)
                if interpretation == "HIGH":
                    if value > 11.1: # Hodnota typická pro diabetes
                         identified_risks.append("Vysoké riziko Diabetes Mellitus (na základě glykémie).")
                         potential_diagnoses.append("Pravděpodobný Diabetes Mellitus (na základě glykémie).")
                    elif value > 7.0: # Hraniční hodnota
                         identified_risks.append("Zvýšené riziko poruchy glukózové tolerance nebo prediabetes (na základě glykémie).")
            except ValueError:
                pass


    if not identified_risks and not potential_diagnoses:
        output = {
            "status": "No significant risks or conditions identified by predictive models.",
            "identified_risks": [],
            "potential_diagnoses_based_on_models": [],
            "model_version": "mock_v0.1"
        }
    else:
        output = {
            "status": "Potential risks or conditions identified.",
            "identified_risks": identified_risks,
            "potential_diagnoses_based_on_models": potential_diagnoses,
            "model_version": "mock_v0.1"
        }

    # V reálném scénáři by zde bylo volání interního API prediktivních modelů
    # nebo přímé spuštění modelů (např. scikit-learn, TensorFlow, PyTorch).
    # Výstup by měl být strukturovaný, např. seznam identifikovaných rizik,
    # pravděpodobnosti onemocnění, doporučení pro další testy atd.

    return output

# Alternativní třídní implementace (pro konzistenci s předchozím, ale lze použít jen @tool)
class PredictiveAnalysisTool(BaseTool):
    name: str = "predictive_analysis_tool"
    description: str = (
        "Spouští (aktuálně mockované) prediktivní AI modely na normalizovaných laboratorních datech. "
        "Identifikuje potenciální patologické stavy, rizikové faktory nebo anomálie. "
        "Použij tento nástroj po normalizaci dat, pokud chceš získat dodatečný vhled z prediktivních modelů."
    )
    args_schema: Type[BaseModel] = PredictiveAnalysisInput
    return_direct: bool = False

    def _run(self, normalized_lab_data: Dict[str, Any]) -> Dict[str, Any]:
        return run_predictive_analysis_func(normalized_lab_data)

    async def _arun(self, normalized_lab_data: Dict[str, Any]) -> Dict[str, Any]:
        return self._run(normalized_lab_data)

if __name__ == '__main__':
    sample_data_normalized = {
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
          "value": "35.0", # Středně zvýšené CRP
          "unit": "mg/L",
          "reference_range_raw": "<5",
          "interpretation_status": "HIGH"
        },
        {
          "parameter_code": "GLUC",
          "parameter_name": "S_Glukóza",
          "value": "12.5", # Vysoká glukóza
          "unit": "mmol/L",
          "reference_range_raw": "3.9-5.6",
          "interpretation_status": "HIGH"
        }
      ]
    }

    # Použití funkce
    predictions_func = run_predictive_analysis_func(sample_data_normalized)
    print("Výstup z prediktivní analýzy (funkce):", json.dumps(predictions_func, indent=2, ensure_ascii=False))

    # Použití nástroje
    tool_instance_pred = PredictiveAnalysisTool()
    predictions_tool = tool_instance_pred.invoke({"normalized_lab_data": sample_data_normalized})
    print("Výstup z prediktivní analýzy (nástroj):", json.dumps(predictions_tool, indent=2, ensure_ascii=False))

    sample_data_normal = {
      "current_lab_results": [
        {"parameter_name": "S_CRP", "value": "2.0", "interpretation_status": "NORMAL"},
        {"parameter_name": "S_Glukóza", "value": "5.0", "interpretation_status": "NORMAL"}
      ]
    }
    predictions_normal = run_predictive_analysis_func(sample_data_normal)
    print("Výstup (normální hodnoty):", json.dumps(predictions_normal, indent=2, ensure_ascii=False))
