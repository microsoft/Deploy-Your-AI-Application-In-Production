# src/ai_engine/core/prompts.py
from langchain_core.prompts import ChatPromptTemplate

# System message definuje roli a základní instrukce pro LLM
SYSTEM_MESSAGE = """Jsi zkušený lékařský diagnostik specializující se na interpretaci laboratorních výsledků.
Tvým úkolem je analyzovat poskytnutá laboratorní data, zohlednit kontext pacienta (pokud je dostupný) a relevantní klinické směrnice.
Generuj srozumitelné, fakticky správné a klinicky relevantní interpretace určené pro vložení do bloku "ME-PopisyNaVL" v lékařské zprávě.
Nikdy si nevymýšlej hodnoty ani fakta, která nejsou podložena v poskytnutých datech nebo znalostní bázi.
Neposkytuj diagnózu, ale pouze interpretaci výsledků a doporučení na základě dat a směrnic.
Dodržuj striktně formát a typ požadovaného popisu (nehrazený, hrazený individuální, hrazený balíčkový).
"""

# Human message obsahuje dynamické části, které budou naplněny konkrétními daty
HUMAN_MESSAGE_TEMPLATE = """Analyzuj následující informace a vygeneruj laboratorní interpretaci.

**Typ požadované interpretace:** {evaluation_method}

**Informace o pacientovi (pokud relevantní a dostupné):**
Věk: {patient_age}
Pohlaví: {patient_gender}
Anamnéza a medikace: {anamnesis_and_medication}
Diagnózy: {diagnoses}
Poznámky lékaře: {doctor_description}
Poznámky k žádance/metodám: {memo_to_request}

**Aktuální laboratorní výsledky:**
{current_lab_results_formatted}

**Kontext z klinických směrnic (RAG):**
{rag_context}

**Výstupy z prediktivních modelů (pokud relevantní):**
{predictive_outputs}

**Specifické instrukce pro typ '{evaluation_method}':**
{specific_instructions}

Poskytni strukturovanou a srozumitelnou interpretaci. Zaměř se na:
1.  Identifikaci a hodnocení abnormálních hodnot (včetně závažnosti).
2.  Vysvětlení klinického významu jednotlivých metod a jejich patologií.
3.  Popis vzájemných vztahů mezi výsledky a jejich relevanci k možným onemocněním nebo stavům.
4.  Zohlednění informací z dotazníku klienta (pokud jsou dostupné a relevantní).
5.  Formulaci jasných doporučení pro další postup (např. konzultace s lékařem, doplňující vyšetření).
6.  Pro výjimky (HCG, PSA, KO, M+S) vždy generuj popis dle specifikace, i když jsou hodnoty v normě.
7.  Pro kumulativní hodnocení (HCG, PSA, hrazené popisy) zohledni historická data, pokud jsou dostupná (v této fázi simulováno nebo naznačeno v `rag_context` či `predictive_outputs`).

Výsledná interpretace by měla být přímo použitelná pro vložení do bloku "ME-PopisyNaVL".
"""

interpretation_prompt = ChatPromptTemplate.from_messages([
    ("system", SYSTEM_MESSAGE),
    ("human", HUMAN_MESSAGE_TEMPLATE)
])

# Doplňkové funkce pro formátování vstupů pro prompt
def format_lab_results_for_prompt(lab_results: list[dict]) -> str:
    if not lab_results:
        return "Žádné laboratorní výsledky nebyly poskytnuty."

    formatted_str = ""
    for result in lab_results:
        line = f"- {result.get('parameter_name', 'N/A')} ({result.get('parameter_code', 'N/A')}): {result.get('value', 'N/A')} {result.get('unit', '')}"
        line += f" (Ref. rozsah: {result.get('reference_range_raw', 'N/A')})"
        line += f" - Interpretace: {result.get('interpretation_status', 'N/A')}"
        if result.get('raw_dasta_skala'):
            line += f" (DASTA škála: {result.get('raw_dasta_skala')})"
        formatted_str += line + "\n"
    return formatted_str

def get_specific_instructions(evaluation_method: str, patient_data: dict, lab_results: list[dict]) -> str:
    """
    Generuje specifické instrukce pro LLM na základě typu požadovaného popisu.
    """
    # TODO: Rozšířit logiku pro různé typy popisů (nehrazený, B1, B2) a výjimky.
    # Tato funkce by měla dynamicky sestavit text instrukcí.
    # Například, pro nehrazený popis: "Generuj popis pouze v případě klinicky významné abnormity, jinak vrať 'Všechny výsledky v normě.'"
    # Pro HCG: "Vždy generuj popis pro HCG, zohledni možné stavy (gravidita, nerozvíjející se gravidita)."
    # Pro PSA: "Vždy generuj popis pro PSA, zohledni věk pacienta a jeho stav."
    # Pro KO a M+S: "Vždy generuj popis, i když jsou výsledky v normě (např. 'Krevní obraz v normě.')."

    instructions = []
    if "NEHRAZENY" in evaluation_method.upper():
        instructions.append("Toto je NEHRAZENÝ popis. Generuj plný popis POUZE v případě záchytu klinicky významné abnormity (mimo explicitní výjimky HCG, PSA, KO, M+S). Pokud jsou všechny hodnoty (mimo výjimek) v normě, uveď pouze stručné konstatování, např. 'Všechny sledované parametry jsou v referenčním rozmezí.'")
        # Detekce abnormit pro nehrazený popis
    # Kódy pro výjimky (HCG, PSA, KO, M+S) by měly být přesně definovány, např. z číselníku.
    # Prozatím používáme textovou shodu v názvu parametru nebo evaluation_method.
    exception_param_names = ["HCG", "PSA", "KREVNÍ OBRAZ", "MOČ + SEDIMENT", "KREVNÍ SKUPINA"] # Přidejte další dle potřeby

    is_exception_case = False
    for res in lab_results:
        param_name_upper = res.get("parameter_name", "").upper()
        if any(ex_name in param_name_upper for ex_name in exception_param_names):
            is_exception_case = True
            break
    if any(ex_name in evaluation_method.upper() for ex_name in exception_param_names):
        is_exception_case = True

    has_significant_abnormality = any(
        res.get("interpretation_status", "NORMAL").upper() not in ["NORMAL", "N/A"] and
        not any(ex_name in res.get("parameter_name", "").upper() for ex_name in exception_param_names)
        for res in lab_results
    )

    if "NEHRAZENY" in evaluation_method.upper():
        if not has_significant_abnormality and not is_exception_case:
            # Pokud není žádná signifikantní abnormalita A NEJEDNÁ se o explicitní výjimku,
            # pak se pro nehrazený popis generuje pouze stručné konstatování.
            # Toto konstatování by měl primárně generovat LLM na základě této instrukce.
            instructions.append("NEHRAZENÝ POPIS: Tento popis je generován pouze v případě klinicky významné abnormity nebo u explicitně definovaných výjimek (HCG, PSA, KO, M+S).")
            instructions.append("Pokud nejsou přítomny žádné klinicky významné abnormity (mimo zmíněné výjimky), uveď pouze stručné konstatování, např. 'Všechny sledované parametry jsou v referenčním rozmezí.'")
        else:
            instructions.append("NEHRAZENÝ POPIS: Zaměř se na popis klinicky významných abnormalit a specifikovaných výjimek.")

    # Specifické instrukce pro výjimky (aplikují se vždy, pokud je daný test přítomen)
    # Používáme přesnější detekci na základě parameter_name, pokud je to možné.
    # Předpoklad: kódy metod 5005, 5024, 5041, 5510 jsou obecné kódy "bloků" a ne jednotlivých testů.
    # Skutečná identifikace HCG, PSA atd. by měla ideálně vycházet z `parameter_code`.

    # HCG
    if any("HCG" in res.get("parameter_name", "").upper() for res in lab_results):
        instructions.append("HCG: Vždy generuj popis – 'svědčí / nesvědčí pro graviditu', nebo 'svědčí pro nerozvíjející se graviditu'. Zohledni kumulativní hodnocení, pokud jsou dostupná historická data.")

    # PSA
    if any("PSA" in res.get("parameter_name", "").upper() or "PROSTATICKÝ SPECIFICKÝ ANTIGEN" in res.get("parameter_name", "").upper() for res in lab_results):
        age_info = f" (věk pacienta: {patient_data.get('age', 'Neznámý')})" if patient_data.get('age') else ""
        instructions.append(f"PSA: Vždy generuj popis. Vyjádři se k výsledku vzhledem k věku pacienta{age_info} a jeho stavu (např. prodělaná operace, léčba). Zohledni kumulativní hodnocení.")

    # Krevní obraz (KO)
    # Detekce KO může být složitější, pokud je to skupina metod. Prozatím zjednodušeno.
    if any("KREVNÍ OBRAZ" in res.get("parameter_name", "").upper() for res in lab_results) or "KO" in evaluation_method.upper():
        instructions.append("KREVNÍ OBRAZ (KO): Vždy doplň text, i když je v normě (např. 'Krevní obraz v normě.' nebo stručný souhrn klíčových parametrů KO).")

    # Moč + Sediment (M+S)
    if any("MOČ + SEDIMENT" in res.get("parameter_name", "").upper() or "MOČOVÝ SEDIMENT" in res.get("parameter_name", "").upper() for res in lab_results) or "M+S" in evaluation_method.upper():
        instructions.append("MOČ + SEDIMENT (M+S): Vždy doplň text, i když je v normě (např. 'Moč a sediment v normě, bez známek močové infekce.' nebo stručný souhrn).")


    if "HRAZENY_POPIS_INDIVIDUALNI" in evaluation_method.upper(): # B1
        instructions.append("Toto je HRAZENÝ INDIVIDUÁLNÍ popis (B1):")
        instructions.append("- Vždy popiš VŠECHNY metody s patologií (hodnocení, závažnost, vysvětlení, vztah).")
        instructions.append("- Zohledni informace z dotazníku klienta (pokud jsou strukturovaně dostupné).")
        instructions.append("- Proveď kumulativní hodnocení DB klienta (celý historický profil).")
        instructions.append("- Stručně zhodnoť i metody v NORMĚ s jejich klinickým významem.")
        instructions.append("- Stanov jednoznačnou 'laboratorní Diagnózu'.")
        instructions.append("- Poskytni detailní doporučení.")

    if "HRAZENY_POPIS_BALICEK" in evaluation_method.upper(): # B2
        instructions.append("Toto je HRAZENÝ BALÍČKOVÝ popis (B2) - NEJPODROBNĚJŠÍ:")
        instructions.append("- Vždy popiš VŠECHNY vyšetřené metody v balíčku.")
        instructions.append("- U metod v referenčním rozmezí (RM) uveď nejen 'v normě', ale také např. 'nesvědčí pro…'.")
        instructions.append("- U metod s patologií zahrň detailní hodnocení trendu patologie (pokud jsou data).")
        instructions.append("- Detailně vysvětli metody/skupiny metod a jejich klinické vazby.")
        instructions.append("- Popiš vztah patologií k uvažovaným onemocněním, vliv interferencí, preanalytické fáze, trendy.")
        instructions.append("- Zohledni informace z dotazníku klienta.")
        instructions.append("- Proveď kumulativní hodnocení DB klienta (včetně jiných metod v historii).")
        instructions.append("- Hodnoť rizikové faktory (AS, OP, DM atd.).")
        instructions.append("- Stanov 'laboratorní Diagnózu' i ve vztahu k terapii.")
        instructions.append("- Poskytni VELMI PODROBNÁ doporučení (lékař, specialista, životospráva, dieta, pohyb, suplementace).")

    if not instructions:
        return "Nebyly poskytnuty žádné specifické instrukce pro tento typ vyhodnocení. Postupuj podle obecných pokynů."

    return "\n".join(instructions)

if __name__ == '__main__':
    # Příklad použití
    sample_patient_data = {
        "gender": "muz",
        "age": 45,
        "historical_data_access_key": "patient_ID_hash_pro_historii"
    }
    sample_lab_results = [
        { "parameter_code": "01001", "parameter_name": "S_CRP", "value": "35.0", "unit": "mg/L", "reference_range_raw": "<5", "interpretation_status": "HIGH", "raw_dasta_skala": "| | ||" }
    ]
    sample_dasta = {
        "doctor_description": "Pacient si stěžuje na únavu.",
        "memo_to_request": "Prosím o zrychlené vyhodnocení.",
        "memo_to_method_01001": None
    }
    sample_diagnoses = ["hypercholesterolemie"]
    sample_anamnesis = {"anamnesis_text": "OA: Art. hypertenze", "medication_text": "FA: Ylpio"}

    formatted_results = format_lab_results_for_prompt(sample_lab_results)
    specific_instr = get_specific_instructions("NEHRAZENY_POPIS_ABNORMITA", sample_patient_data, sample_lab_results)

    prompt_input = {
        "evaluation_method": "NEHRAZENY_POPIS_ABNORMITA",
        "patient_age": sample_patient_data.get("age"),
        "patient_gender": sample_patient_data.get("gender"),
        "anamnesis_and_medication": f"Anamnéza: {sample_anamnesis.get('anamnesis_text')}, Medikace: {sample_anamnesis.get('medication_text')}",
        "diagnoses": ", ".join(sample_diagnoses) if sample_diagnoses else "Nezadáno",
        "doctor_description": sample_dasta.get("doctor_description") or "Nezadáno",
        "memo_to_request": sample_dasta.get("memo_to_request") or "Nezadáno",
        "current_lab_results_formatted": formatted_results,
        "rag_context": "Pro CRP > 10 mg/L u dospělých zvažte bakteriální infekci nebo jiný zánětlivý stav.",
        "predictive_outputs": "Nezadáno",
        "specific_instructions": specific_instr
    }

    # Vygenerování promptu
    # compiled_prompt = interpretation_prompt.invoke(prompt_input)
    # print(compiled_prompt.to_string())
    pass
