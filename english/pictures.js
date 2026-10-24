// Picture cue for every word: 1–3 emoji that hint at the meaning (dual coding: word + image).
// Keyed by the word exactly as in words.js. A word without an entry simply shows no picture.
window.WORD_PICS = {
// 1 One Health
"outbreak":"🐖🦠💥","surveillance":"🔍🐄📋","zoonotic":"🐕➡️🧑","transmission":"🦠➡️🐖","mitigate":"🛡️📉",
"prevalence":"📊🐖","stakeholder":"👨‍🌾🧑‍⚕️🏛️","contain":"🚧🦠","livelihood":"👨‍🌾🐖💰","mandatory":"📜❗",
// 2 Examination
"lethargic":"🐄💤","dehydrated":"🐖🚱","lesion":"👅🔴","lameness":"🐄🦵","inflammation":"🔥🔴",
"abscess":"🐐🔴","prognosis":"🩺🔮","palpate":"✋🐄","auscultation":"🩺👂","chronic":"⏳📅",
// 3 Treatment
"dosage":"💊⚖️","administer":"💉🐕","adverse":"💊⚠️","contraindication":"💊🚫","efficacy":"💊✅",
"prescribe":"🧑‍⚕️📝💊","resistance":"🦠🛡️💊","intravenous":"💉🩸","withdrawal period":"💊⏳🥛","compliance":"📋✅",
// 4 Research
"hypothesis":"💡❓","sample size":"🐖🐖🐖🔢","variable":"🔀📊","methodology":"🧪📋","bias":"⚖️👀",
"significant":"📊⭐","correlation":"📈🔗","respondent":"🙋📝","questionnaire":"📝❓","cross-sectional":"📸⏱️",
// 5 Academic verbs
"demonstrate":"👨‍🏫📊","indicate":"👉📈","highlight":"🖍️⭐","suggest":"💭👉","emphasise":"❗📢",
"illustrate":"🖼️✏️","contribute":"🧩➕","undermine":"⛏️🧱","facilitate":"🛤️✅","enhance":"⬆️✨",
// 6 Livestock production
"livestock":"🐄🐖🐐","herd":"🐄🐄🐄","flock":"🐑🐔🐑","yield":"🥛📈","fodder":"🌾🐄",
"breeding":"🐂❤️🐄","calving":"🐄🐮","weaning":"🍼🚫🐷","carcass":"🥩🐄","productivity":"🏭📈",
// 7 Biosecurity
"biosecurity":"🛡️🦠🚜","disinfect":"🧴🦠❌","quarantine":"🏠🔒🐄","contaminated":"💧☣️","pathogen":"🦠",
"vector":"🦟🦠","carrier":"🐄🦠🙂","footbath":"🥾🪣","isolate":"🐖↔️🐖","restrict":"🚫🚚",
// 8 Aquatic health
"aquaculture":"🐟🏞️","gill":"🐟🫁","fingerling":"🐟🤏","stocking density":"🐟🐟🐟🐟","dissolved oxygen":"💧🫧",
"water quality":"💧🔬","hatchery":"🥚🐟","mortality":"🐟📉","parasite":"🪱","feed conversion ratio":"🌾➡️🥩",
// 9 Wildlife
"endangered":"🐘⚠️","habitat":"🌳🐒","poaching":"🐘🚫🔫","conservation":"🌿🐯🛡️","captive":"🐒🔒",
"sedate":"💉😴","biodiversity":"🐦🦋🐸","trafficking":"🦜📦🚫","rehabilitation":"🐯🩹","release":"🦅🌳",
// 10 Linking words
"however":"↩️","moreover":"➕➕","consequently":"➡️🎯","nevertheless":"🤷➡️","whereas":"⚖️↔️",
"furthermore":"➕","therefore":"∴➡️","despite":"🌧️🚶","in contrast":"⬛⬜","as a result":"🔗🎯",
// 11 Describing graphs
"fluctuate":"📈📉📈","peak":"⛰️🔝","plummet":"📉⬇️","surge":"🚀📈","steady":"➖➡️",
"decline":"📉","gradual":"🐢📈","remain stable":"➖⚖️","account for":"🥧🔢","proportion":"🥧📐",
// 12 Opinion essays
"advocate":"📣👍","controversial":"🗣️⚡🗣️","drawback":"👎","benefit":"👍🎁","perspective":"👓🌍",
"justify":"⚖️💬","inevitable":"⏳🎯","crucial":"🔑❗","detrimental":"☠️📉","beneficial":"🌱👍",
// 13 Public health & zoonoses
"spillover":"🦇➡️🧑","reservoir":"🦇🦠","host":"🐖🏠🦠","immunity":"🛡️🧬","incubation period":"🦠⏳🤒",
"susceptible":"🧑🎯🦠","pandemic":"🌍🦠","endemic":"🏘️🦠","epidemic":"🏙️🦠📈","notifiable":"📞🏛️❗",
// 14 Vaccines
"vaccinate":"💉🐄","booster":"💉➕","coverage":"☂️🐄🐄","cold chain":"❄️🚚💉","antibody":"🛡️🔒🦠",
"antigen":"🦠🏷️","herd immunity":"🐄🐄🛡️","attenuated":"🦠😴","potency":"💪💉","campaign":"📢💉",
// 15 Laboratory
"specimen":"🧪🩸","culture":"🧫🦠","stain":"🔬🟣","centrifuge":"🌀🧪","assay":"🧪✅",
"sterile":"✨🧤","reagent":"⚗️🧪","false positive":"➕❌","sensitivity":"🎯🦠","confirm":"✅🔬",
// 16 Surgery & anaesthesia
"anaesthesia":"😴💉","incision":"🔪📏","suture":"🪡🧵","aseptic":"🧤✨","haemorrhage":"🩸⚠️",
"sedation":"😌💉","postoperative":"🏥🛏️","wound":"🩹","castration":"✂️🐖","recovery":"🐕💪",
// 17 Reproduction
"oestrus":"🐄❤️","gestation":"🐄🤰⏳","artificial insemination":"🐄💉🧬","fertility":"🌱🐄","dystocia":"🐄🆘",
"placenta":"🤰🔗","lactation":"🐄🥛","abortion":"🐄💔","heifer":"🐮🌱","offspring":"🐖🐷🐷",
// 18 Nutrition
"nutrient":"🥦🧪","deficiency":"🔋📉","supplement":"💊🌾","ration":"🥣⚖️","digestible":"🌾✅",
"forage":"🌿🐄","mineral":"🧂💎","malnutrition":"🐄🦴","concentrate":"🌽🥜","appetite":"🐖🍽️",
// 19 Economics & development
"smallholder":"👨‍🌾🏡🐖","subsidy":"🏛️💵","market access":"🚚🏪","profitable":"💰📈","investment":"💵🌱",
"poverty":"🏚️","sustainable":"♻️🌱","value chain":"🐄➡️🏭➡️🏪","revenue":"💵⬆️","cost-effective":"💰👍",
// 20 Policy & international organisations
"policy":"🏛️📜","regulation":"📏📜","guideline":"🧭📘","implement":"🛠️📜","capacity building":"🧱📈👩‍🎓",
"collaboration":"🤝","partnership":"🤝🌍","funding":"💰🏦","mandate":"📜👉","evaluate":"📋✅❌",
// 21 Communicating with farmers
"advise":"🧑‍⚕️💬👨‍🌾","reassure":"🤗","concern":"😟","persuade":"🗣️👉","awareness":"💡👀",
"misconception":"❌💭","practical":"🛠️👍","feedback":"💬↩️","trust":"🤝❤️","convey":"📨💬",
// 22 Environment & climate
"climate change":"🌍🌡️","drought":"☀️🏜️","flooding":"🌊🏠","emission":"🏭💨","heat stress":"🐄🥵",
"resilience":"🌱💪","adapt":"🦎🔄","degradation":"🏜️📉","seasonal":"🌧️☀️","pollution":"🏭☁️🚯",
// 23 Data & statistics
"average":"➗📊","median":"📍📊","percentage":"％","estimate":"🤔🔢","trend":"📈",
"survey":"📋🏘️","analyse":"🔬📊","interpret":"🧠📊","outlier":"📊❗","confidence interval":"↔️📊",
// 24 Emails & meetings
"agenda":"📋🗓️","deadline":"⏰📅","follow up":"📧🔁","attach":"📎","clarify":"💡💬",
"postpone":"📅➡️","minutes":"📝🗣️","propose":"🙋💡","available":"🟢📅","regarding":"📌✉️",
// 25 Food safety
"food safety":"🍖✅","residue":"💊🥩","slaughterhouse":"🏭🐄","inspection":"🔍🥩","hygiene":"🧼🙌",
"spoilage":"🥩🤢","traceability":"🏷️🔍🐄","shelf life":"🥫📅","foodborne":"🍗🦠","contamination":"💧☣️",
// 26 Basic anatomy
"abdomen":"🐄⭕","thorax":"🫁❤️","rumen":"🐄🌾🫃","liver":"🟤🫀","kidney":"🫘",
"spleen":"🟣🩸","lymph node":"⚪🛡️","trachea":"🫁🌬️","intestine":"〰️🍽️","udder":"🐄🥛",
// 27 Disease verbs
"spread":"🦠➡️🦠🦠","affect":"🎯🐖","prevent":"🛡️🚫","detect":"🔍🦠","eradicate":"🦠❌🧹",
"emerge":"🌱🦠","persist":"⏳🦠","trigger":"🔫💥","worsen":"📉🤒","recover":"🤒➡️💪",
// 28 Personal qualities
"reliable":"⏰✅","adaptable":"🦎🔄","motivated":"🔥🏃","proactive":"🚀👀","collaborative":"🤝👥",
"meticulous":"🔍✏️","committed":"💪❤️","empathetic":"🤗💭","organised":"🗂️✅","initiative":"💡🚀",
// 29 Society & development
"urbanisation":"🏙️🏗️","rural":"🌾🏡","population growth":"👥📈","consumption":"🍽️🛒","globalisation":"🌍✈️",
"infrastructure":"🛣️🌉⚡","affordable":"💵👍","access":"🚪➡️","migration":"🧳🏙️","demand":"🛒📈",
// 30 Academic Word List
"approach":"🧭","evidence":"🔎📄","factor":"🧩","framework":"🏗️📐","impact":"💥🎯",
"issue":"❓⚠️","method":"📋🔧","principle":"⚖️📜","role":"🎭👤","strategy":"♟️🗺️"
};
