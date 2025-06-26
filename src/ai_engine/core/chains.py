# src/ai_engine/core/chains.py
import json
from typing import Dict, Any, Optional, Union
from langchain_core.runnables import RunnablePassthrough, RunnableLambda, RunnableParallel
from langchain_core.output_parsers import StrOutputParser
from ..tools.lab_data_normalizer import normalize_lab_data_func
from ..tools.predictive_analysis import run_predictive_analysis_func
from ..tools.rag_retrieval import retrieve_clinical_guidelines_func
from .prompts import interpretation_prompt, format_lab_results_for_prompt, get_specific_instructions
from .llm import get_llm

def prepare_llm_input(processed_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Formátuje data pro vložení do hlavního interpretačního promptu LLM.
    """
    normalized_data = processed_data.get("normalized_data", {})
    if isinstance(normalized_data, str): # Může se stát, pokud normalizace selže a vrátí string error
        normalized_data = {"error_in_normalization": normalized_data}

    patient_metadata = normalized_data.get("patient_metadata", {})
    current_lab_results = normalized_data.get("current_lab_results", [])
    dasta_sections = normalized_data.get("dasta_text_sections", {})
    diagnoses = normalized_data.get("diagnoses", [])
    anamnesis = normalized_data.get("anamnesis_and_medication", {})

    llm_input = {
        "evaluation_method": normalized_data.get("evaluation_method", "Neznámá metoda vyhodnocení"),
        "patient_age": patient_metadata.get("age", "Nezadáno"),
        "patient_gender": patient_metadata.get("gender", "Nezadáno"),
        "anamnesis_and_medication": f"Anamnéza: {anamnesis.get('anamnesis_text', 'Nezadáno')}, Medikace: {anamnesis.get('medication_text', 'Nezadáno')}",
        "diagnoses": ", ".join(diagnoses) if diagnoses else "Nezadáno",
        "doctor_description": dasta_sections.get("doctor_description", "Nezadáno"),
        "memo_to_request": dasta_sections.get("memo_to_request", "Nezadáno"), # TODO: Zvážit i memo k metodám
        "current_lab_results_formatted": format_lab_results_for_prompt(current_lab_results),
        "rag_context": processed_data.get("rag_context", "Nebyly nalezeny žádné relevantní klinické směrnice."),
        "predictive_outputs": json.dumps(processed_data.get("predictive_outputs", {"status": "Prediktivní analýza nebyla provedena."}), indent=2, ensure_ascii=False),
        "specific_instructions": get_specific_instructions(
            normalized_data.get("evaluation_method", ""),
            patient_metadata, # patient_data
            current_lab_results # lab_results
        )
    }
    return llm_input

def generate_rag_query(processed_data: Dict[str, Any]) -> str:
    """
    Generuje dotaz pro RAG na základě normalizovaných dat a prediktivních výstupů.
    """
    normalized_data = processed_data.get("normalized_data", {})
    predictive_outputs = processed_data.get("predictive_outputs", {})

    # Extrahujeme názvy parametrů s abnormálními hodnotami
    abnormal_params = [
        res.get("parameter_name")
        for res in normalized_data.get("current_lab_results", [])
        if res.get("interpretation_status", "NORMAL").upper() != "NORMAL" and res.get("parameter_name")
    ]

    # Extrahujeme identifikovaná rizika z prediktivní analýzy
    identified_risks = predictive_outputs.get("identified_risks", [])

    # Sestavíme dotaz
    query_parts = []
    if abnormal_params:
        query_parts.append(f"Interpretace pro abnormální parametry: {', '.join(abnormal_params)}")
    if identified_risks:
        query_parts.append(f"Klinické informace k rizikům: {', '.join(identified_risks)}")

    # Fallback, pokud nic specifického není
    if not query_parts:
        # Můžeme vzít první parametr nebo obecný dotaz
        first_param_name = normalized_data.get("current_lab_results", [{}])[0].get("parameter_name", "laboratorní výsledky")
        query_parts.append(f"Obecné informace k {first_param_name}")

    return " ".join(query_parts)


# Hlavní LCEL řetězec pro AI Engine
# Používáme RunnableParallel pro souběžné (kde to dává smysl) nebo sekvenční zpracování
# s jasným předáváním dat mezi kroky.

# Krok 1: Normalizace vstupních dat
# Vstup: {"raw_json_input": "..."}
# Výstup: {"raw_json_input": "...", "normalized_data": {...}}
chain_normalize = RunnablePassthrough.assign(
    normalized_data=RunnableLambda(lambda x: normalize_lab_data_func(x["raw_json_input"]))
)

# Krok 2: Prediktivní analýza (na základě normalizovaných dat)
# Vstup: Výstup z chain_normalize
# Výstup: {"raw_json_input": "...", "normalized_data": {...}, "predictive_outputs": {...}}
chain_predict = RunnablePassthrough.assign(
    predictive_outputs=RunnableLambda(lambda x: run_predictive_analysis_func(x["normalized_data"]))
)

# Krok 3: Generování dotazu pro RAG a samotné RAG vyhledávání
# Vstup: Výstup z chain_predict
# Výstup: {"raw_json_input": "...", "normalized_data": {...}, "predictive_outputs": {...}, "rag_query": "...", "rag_context": "..."}
chain_rag = RunnablePassthrough.assign(
    rag_query=RunnableLambda(generate_rag_query),
    # rag_context se přidá v dalším kroku, protože potřebuje rag_query
)
chain_rag = chain_rag.assign(
    rag_context=RunnableLambda(lambda x: retrieve_clinical_guidelines_func(x["rag_query"]))
)


# Krok 4: Příprava finálního vstupu pro LLM a volání LLM
# Vstup: Výstup z chain_rag
# Výstup: String (finální interpretace)
chain_llm = (
    RunnableLambda(prepare_llm_input) # Připraví slovník pro prompt template
    | interpretation_prompt             # Vloží hodnoty do promptu
    | get_llm()                         # Získá instanci LLM
    | StrOutputParser()                 # Převede výstup LLM na string
)

# Celkový AI Engine řetězec
# Tento řetězec spojuje všechny předchozí kroky.
# Pořadí je důležité: normalizace -> predikce -> RAG -> LLM
ai_engine_chain = (
    chain_normalize
    | chain_predict
    | chain_rag
    | chain_llm
)


# Pro testování
if __name__ == "__main__":
    sample_raw_json_input = """
    {
      "request_id": "GUID_TEST_123",
      "evaluation_method": "HRAZENY_POPIS_BALICEK_TEST",
      "patient_metadata": {
        "gender": "žena",
        "age": 35,
        "historical_data_access_key": "pid_hash_789"
      },
      "current_lab_results": [
        {
          "parameter_code": "01001",
          "parameter_name": "S_CRP",
          "value": "8.0",
          "unit": "mg/L",
          "reference_range_raw": "<5",
          "interpretation_status": "HIGH",
          "raw_dasta_skala": "| | |H"
        },
        {
          "parameter_code": "GLUC",
          "parameter_name": "S_Glukóza",
          "value": "6.5",
          "unit": "mmol/L",
          "reference_range_raw": "3.9-5.6",
          "interpretation_status": "HIGH",
          "raw_dasta_skala": "| | |H"
        },
        {
          "parameter_code": "HCG",
          "parameter_name": "S_HCG",
          "value": "1500",
          "unit": "mIU/mL",
          "reference_range_raw": "<5",
          "interpretation_status": "HIGH",
          "raw_dasta_skala": "HCG_HIGH"
        }
      ],
      "dasta_text_sections": {
        "doctor_description": "Pacientka přichází na preventivní prohlídku, udává únavu.",
        "memo_to_request": "Prosím o komplexní zhodnocení v rámci balíčku 'Zdraví ženy'."
      },
      "diagnoses": [
        "Mírná anémie v minulosti"
      ],
      "anamnesis_and_medication": {
        "anamnesis_text": "OA: bez vážnějších onemocnění, občasné migrény. GA: 1x porod.",
        "medication_text": "FA: Magnosolv při migréně."
      }
    }
    """

    print("--- Testování ai_engine_chain ---")

    # Pro spuštění tohoto testu je potřeba mít nastavené proměnné prostředí pro Azure OpenAI
    # (AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY, AZURE_OPENAI_CHAT_DEPLOYMENT_NAME)
    # a také nainstalované potřebné knihovny (langchain, langchain-openai, pydantic, python-dotenv).

    # Pokud nemáte nastavené Azure OpenAI, můžete testovat části chainu samostatně
    # nebo mockovat LLM. Pro jednoduchost zde předpokládáme, že je LLM dostupné.

    try:
        final_interpretation = ai_engine_chain.invoke({"raw_json_input": sample_raw_json_input})
        print("\n--- Finální Interpretace ---")
        print(final_interpretation)
    except Exception as e:
        print(f"\nChyba při spouštění ai_engine_chain: {e}")
        print("Ujistěte se, že máte správně nastavené proměnné prostředí pro Azure OpenAI.")
        print("Např. AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY, AZURE_OPENAI_CHAT_DEPLOYMENT_NAME.")

    # Příklad testování dílčí části (např. normalizace a predikce)
    print("\n--- Testování dílčí části (normalizace + predikce) ---")
    partial_chain = chain_normalize | chain_predict
    try:
        intermediate_output = partial_chain.invoke({"raw_json_input": sample_raw_json_input})
        print(json.dumps(intermediate_output, indent=2, ensure_ascii=False))
    except Exception as e:
        print(f"Chyba při spouštění dílčího řetězce: {e}")

    print("\n--- Testování dílčí části (normalizace + predikce + RAG) ---")
    partial_chain_rag = chain_normalize | chain_predict | chain_rag
    try:
        intermediate_output_rag = partial_chain_rag.invoke({"raw_json_input": sample_raw_json_input})
        print(json.dumps(intermediate_output_rag, indent=2, ensure_ascii=False))
    except Exception as e:
        print(f"Chyba při spouštění dílčího řetězce s RAG: {e}")

    print("\n--- Testování přípravy vstupu pro LLM ---")
    # Krok 1, 2, 3
    processed_data_for_llm_prep = (chain_normalize | chain_predict | chain_rag).invoke({"raw_json_input": sample_raw_json_input})
    # Krok 4a - příprava vstupu
    llm_input_data = prepare_llm_input(processed_data_for_llm_prep)
    print(json.dumps(llm_input_data, indent=2, ensure_ascii=False))

    # Test get_specific_instructions (samostatně)
    print("\n--- Testování get_specific_instructions ---")
    normalized_sample = normalize_lab_data_func(sample_raw_json_input)
    instr = get_specific_instructions(
        normalized_sample.get("evaluation_method"),
        normalized_sample.get("patient_metadata"),
        normalized_sample.get("current_lab_results")
    )
    print(instr)

    instr_nehrazeny_normal = get_specific_instructions(
        "NEHRAZENY_POPIS_NORMAL",
        {"age": 30, "gender": "muz"},
        [{"parameter_name": "Cholesterol", "value": "5.0", "interpretation_status": "NORMAL"}]
    )
    print(f"\nNehrazený normální:\n{instr_nehrazeny_normal}")

    instr_b1 = get_specific_instructions(
        "HRAZENY_POPIS_INDIVIDUALNI_TEST",
        {"age": 50, "gender": "žena"},
        [{"parameter_name": "S_Glukóza", "value": "8.0", "interpretation_status": "HIGH"}]
    )
    print(f"\nHrazený B1:\n{instr_b1}")

    instr_b2_psa = get_specific_instructions(
        "HRAZENY_POPIS_BALICEK_PSA_MUZ",
        {"age": 65, "gender": "muz"},
        [{"parameter_name": "S_PSA", "value": "4.5", "interpretation_status": "HIGH"}]
    )
    print(f"\nHrazený B2 (PSA):\n{instr_b2_psa}")

    pass
