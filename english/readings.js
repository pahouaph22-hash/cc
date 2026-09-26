// One reading passage per vocabulary set (same order as words.js).
// Every passage uses all ten words of its set. Paragraphs are separated by blank lines.
// Each question: [question, [correct answer, wrong, wrong, wrong]] — options are shuffled on the page.
window.READINGS = [
{title:"Stopping an Outbreak Before It Spreads", text:`Last year, an outbreak of African swine fever hit several villages in southern Laos. Within two weeks, hundreds of pigs had died, and many families lost their main source of income. For smallholders, pigs are more than animals; they are savings, school fees and a safety net. When the disease arrived, their livelihoods were suddenly at risk.

The district veterinary team acted quickly to contain the virus. They closed pig markets, stopped animal movement and made reporting of sick pigs mandatory. At the same time, they strengthened surveillance by visiting farms every week and collecting blood samples. The results showed that the prevalence of the disease was highest in villages near the main road, which suggested that trucks played a role in transmission.

African swine fever is not a zoonotic disease, so it does not infect people. However, the team used a One Health approach because many stakeholders were involved: farmers, traders, local leaders and health officers. Working together, they were able to mitigate the damage and protect the remaining pigs.`,
questions:[
["Why were families worried when the disease arrived?",["They could lose an important source of income","The disease could infect their children","Pig prices were too low","The government closed the schools"]],
["Where was the prevalence of the disease highest?",["In villages near the main road","In the mountains","In the capital city","In villages far from any road"]],
["Why did the team use a One Health approach even though the disease is not zoonotic?",["Many different groups were involved","The virus also infects humans","Doctors asked them to","It was the cheapest option"]]]},

{title:"A Morning at the Clinic", text:`On Monday morning, a farmer brought a young goat to the university clinic. The animal was lethargic and had not eaten for two days. Its eyes were sunken and its skin stayed up when pinched, clear signs that it was dehydrated.

Our teacher asked me to examine the goat step by step. First, I checked its temperature and gums. Then I used auscultation to listen to the heart and lungs, which sounded normal. When I began to palpate the neck, I felt a soft, warm swelling. It was an abscess, and the redness around it showed there was inflammation.

We also noticed mild lameness in the left back leg and a small lesion on the foot. The farmer said the goat had been limping for months, so this was probably a chronic problem.

We drained the abscess, gave fluids and cleaned the foot. Because we started treatment early, the prognosis is good, and the farmer will bring the goat back next week.`,
questions:[
["What showed that the goat was dehydrated?",["Sunken eyes and skin that stayed up when pinched","A high temperature","Abnormal lung sounds","A swelling on the neck"]],
["What did the student find on the goat's neck?",["An abscess","A broken bone","A large tick","Nothing unusual"]],
["Why is the prognosis good?",["Treatment started early","The goat is very old","The lameness disappeared by itself","The farmer sold the goat"]]]},

{title:"Using Antibiotics Responsibly", text:`Antibiotics save many animal lives, but they must be used carefully. When a vet decides to prescribe an antibiotic, the first step is to calculate the correct dosage from the animal's body weight. Giving too little can fail to cure the infection, while giving too much can cause adverse effects such as diarrhoea or kidney damage.

Vets must also check for any contraindication. Some drugs, for example, should not be given to pregnant animals. The way we administer a drug also matters. In a severely ill cow, intravenous treatment works faster than an injection into the muscle.

Farmers play a key role too. Poor compliance, such as stopping treatment early because the animal looks better, is one reason for antimicrobial resistance. When bacteria become resistant, the efficacy of common drugs falls, and simple infections become hard to treat.

Finally, milk and meat from treated animals cannot be sold during the withdrawal period. This protects consumers from drug residues.`,
questions:[
["What is the first step after a vet decides to prescribe an antibiotic?",["Calculate the dosage from body weight","Sell the milk","Give the drug intravenously","Ask the farmer for payment"]],
["Which cause of antimicrobial resistance does the text mention?",["Stopping treatment too early","Using clean needles","Weighing the animal","Vaccinating calves"]],
["Why can't milk be sold during the withdrawal period?",["To protect consumers from drug residues","Because the cow is pregnant","Because milk prices are low","Because the drug changes the taste"]]]},

{title:"Planning My First Research Project", text:`For my final-year project, I want to study rabies vaccination among dog owners. My hypothesis is that owners who have attended a training session are more likely to vaccinate their dogs.

I plan to carry out a cross-sectional study in three districts. My supervisor helped me calculate the sample size, and we decided to interview 200 owners. Each respondent will answer a short questionnaire about their dogs, their income and their knowledge of rabies. These answers will become the variables in my analysis.

The methodology must be clear so that other researchers can repeat it. I also need to think about bias. If I only visit houses near the main road, my results may not represent poorer families in remote areas, so I will choose villages at random.

After collecting the data, I will look for a correlation between training and vaccination. If the difference between the two groups is statistically significant, I can recommend more training programmes.`,
questions:[
["What is the student's hypothesis?",["Owners who attended training are more likely to vaccinate","Dogs in cities are healthier","Rabies is rare in Laos","Poorer families own more dogs"]],
["How many dog owners will be interviewed?",["200","20","3","2,000"]],
["Why will the villages be chosen at random?",["To reduce bias","To save petrol","Because the supervisor lives there","To finish the project faster"]]]},

{title:"What the Report Found", text:`A new report on village animal health workers was published last month. Its findings demonstrate that trained local workers can greatly improve disease reporting in rural areas.

The data indicate that villages with a trained worker reported outbreaks five days earlier than villages without one. The authors suggest that this is because farmers trust someone from their own community. A map in the report clearly illustrates how quickly reports reached district offices.

The report also highlights several problems. Many workers do not have enough vaccines or transport, and some have not been paid for months. According to the authors, these problems undermine the whole system, because workers who are not supported often leave their jobs.

The authors emphasise that money alone is not enough. Mobile phones and simple reporting apps can facilitate communication, while regular refresher courses can enhance workers' skills. They conclude that local workers contribute a great deal to national disease control and deserve stronger support.`,
questions:[
["How much earlier did villages with a trained worker report outbreaks?",["Five days","Five weeks","One day","They did not report earlier"]],
["Which problem does the report highlight?",["Workers lack vaccines, transport and pay","Farmers dislike vaccines","There are too many workers","Phones are too expensive"]],
["According to the authors, what can facilitate communication?",["Mobile phones and simple apps","More meetings in the capital","Printed newspapers","Higher taxes"]]]},

{title:"A Year on a Small Dairy Farm", text:`Mr Somchai keeps a herd of twelve dairy cows and a flock of about fifty chickens near Vientiane. Like many farmers, he depends on livestock for most of his income.

The busiest time of year is calving, which usually happens at the start of the rainy season. After calving, his main goal is to keep the milk yield high. To do this, the cows need good nutrition, so he grows grass and stores fodder for the dry months, when fresh grass is hard to find.

Weaning is another important stage. The calves are separated from their mothers at about three months, and Mr Somchai watches them closely, because stress at this time can make them sick.

He has also invested in better breeding. By using a stronger bull, he has improved the size and health of his young stock. Last year, one old cow died suddenly, and he called the vet to examine the carcass. It was a reminder that good health is the key to farm productivity.`,
questions:[
["When does calving usually happen on this farm?",["At the start of the rainy season","In the coldest month","Every week","At the end of the year"]],
["Why does Mr Somchai store fodder?",["Fresh grass is hard to find in the dry months","He sells it at the market","The cows dislike fresh grass","The vet told him to burn it"]],
["Why did he call the vet after a cow died?",["To examine the carcass","To sell the meat","To buy a new bull","To vaccinate the chickens"]]]},

{title:"Keeping Diseases Out of the Farm", text:`The best way to protect a farm from disease is to stop pathogens from getting in. This is the idea behind biosecurity.

At the entrance of a good pig farm, you will find a footbath filled with disinfectant. Every visitor must step into it and disinfect their boots and hands. Many farms also restrict entry to staff only, because people, vehicles and equipment can all carry germs from farm to farm.

New animals are another risk. Even if they look healthy, they may be carriers of a virus without showing signs. For this reason, they should stay in quarantine for about thirty days before joining the rest of the herd. If any animal becomes sick, the farmer should isolate it immediately.

Feed and water can also be contaminated, so they must be stored in clean, closed containers. Finally, insects such as flies and mosquitoes can act as a vector for some diseases, so farms need good drainage and insect control.`,
questions:[
["What must every visitor do at the farm entrance?",["Step into the footbath and disinfect","Pay an entry fee","Feed the pigs","Take photographs"]],
["How long should new animals stay in quarantine?",["About thirty days","One day","One year","They do not need quarantine"]],
["Why can healthy-looking new animals be dangerous?",["They may be carriers of a virus","They eat too much","They are too expensive","They cannot adapt to the weather"]]]},

{title:"Why the Fish Were Dying", text:`Aquaculture is growing fast in Laos, and many families now raise tilapia in small ponds. Last month, a farmer called our team because mortality in his pond had suddenly increased.

When we arrived early in the morning, we saw fish gasping at the surface. We measured the water quality and found that dissolved oxygen was very low. The farmer explained that he had bought 8,000 fingerlings from a hatchery, far more than the pond could hold. This high stocking density meant that the fish used up oxygen quickly, especially at night.

Next, we examined several fish. Their gill tissue was pale and swollen, and under the microscope we found a parasite on the skin. Stressed fish are more likely to become infected.

We advised him to reduce the number of fish, add an aerator and feed less. Overfeeding pollutes the water and gives a poor feed conversion ratio, which means he pays more for food but gets less growth.`,
questions:[
["Why were the fish gasping at the surface?",["Dissolved oxygen was very low","The water was too cold","They were hungry","The sun was too bright"]],
["What was the problem with the stocking density?",["There were too many fish for the pond","There were too few fish","The fingerlings were too old","The pond was too deep"]],
["What problem does overfeeding cause?",["It pollutes the water and wastes money","It makes fish grow too fast","It kills parasites","It raises oxygen levels"]]]},

{title:"A Second Chance for a Pangolin", text:`Pangolins are among the most trafficked mammals in the world. All species are now endangered, mainly because of poaching for their meat and scales.

Last year, police stopped a car at the border and found three pangolins in a bag. The animals were weak and covered in small wounds. They were taken to a wildlife rehabilitation centre, where vets prepare rescued animals for life back in the wild.

To examine the smallest pangolin safely, the vet had to sedate it. She cleaned its wounds, gave fluids and checked it for parasites. Over the next two months, the pangolins lived in a quiet captive enclosure and slowly gained weight.

When they were strong enough, the team chose a protected forest with a suitable habitat and plenty of ants and termites, and carried out the release at night. This case shows how vets contribute to conservation. Protecting each species helps to protect biodiversity, and stopping wildlife trafficking also reduces the risk of new diseases spreading to people.`,
questions:[
["Why are pangolins endangered?",["Mainly because of poaching","Because of heavy rain","Because they eat too many ants","Because of old age"]],
["Why did the vet sedate the smallest pangolin?",["To examine it safely","To make it sleep for a month","To prepare it for sale","To release it immediately"]],
["Where did the team release the pangolins?",["In a protected forest with suitable habitat and food","At the nearest market","In a city park","At the border crossing"]]]},

{title:"Vaccination: Worth the Cost?", text:`Some farmers in my village do not vaccinate their chickens because vaccines cost money. However, the evidence shows that vaccination saves money in the long run.

Newcastle disease can kill almost a whole flock in a few days. Farmers who vaccinate, in contrast, rarely lose more than a few birds. Moreover, vaccinated chickens grow better, because they are not weakened by disease. Furthermore, healthy birds can be sold at a higher price.

Last year, a neighbour decided not to vaccinate. Consequently, when the disease arrived, he lost nearly all of his chickens. As a result, his family had no eggs to sell for several months. His brother lost none, whereas he lost almost everything.

Despite these clear benefits, some families still say they cannot afford the vaccine. Therefore, our district now offers a small subsidy. Vaccination is not free; nevertheless, it is one of the best investments a farmer can make.`,
questions:[
["What happened to the neighbour who did not vaccinate?",["He lost nearly all his chickens","His chickens grew faster","He sold more eggs","Nothing happened"]],
["Why do vaccinated chickens grow better?",["They are not weakened by disease","They eat less","They are a different breed","They sleep more"]],
["What does the district offer now?",["A small subsidy for vaccines","Free chickens","A new market","Cheaper feed"]]]},

{title:"Describing a Graph: Pig Numbers, 2015–2025", text:`The line graph shows the number of pigs in one province between 2015 and 2025.

From 2015 to 2018, pig numbers showed a steady increase, rising from 80,000 to about 110,000. They then fluctuated slightly for a year before they peaked at 120,000 in 2019.

In 2020, the situation changed dramatically. After African swine fever arrived, numbers plummeted to just 40,000 in less than twelve months. During this period, small village farms accounted for most of the losses, while large commercial farms lost a much smaller proportion of their animals.

Since 2021, there has been a gradual recovery, although the decline in the number of small farms has continued. From 2023 to 2025, the total remained stable at around 90,000. At the same time, there was a surge in demand for pork from neighbouring countries, which suggests that production may grow again in the future.`,
questions:[
["In which year did pig numbers peak?",["2019","2015","2020","2025"]],
["What happened in 2020?",["Numbers plummeted after African swine fever arrived","Numbers doubled","Numbers stayed the same","Many new farms opened"]],
["Which farms accounted for most of the losses?",["Small village farms","Large commercial farms","Fish farms","Chicken farms"]]]},

{title:"Should Healthy Animals Be Culled?", text:`During a serious outbreak, governments sometimes order the culling of all animals near an infected farm, even healthy ones. This is one of the most controversial policies in animal health.

Many experts advocate culling because it can stop a disease quickly. From their perspective, the loss of some healthy animals is acceptable if it protects thousands of others. They argue that fast action is crucial, and that without it, a much larger outbreak is inevitable.

However, the policy has a serious drawback. For poor families, losing every animal can be detrimental to their health, education and future. If compensation is too low or arrives late, farmers may hide sick animals, which makes control even harder.

In my opinion, culling can be beneficial, but only when it is combined with fair and fast compensation. The main benefit of this approach is trust: when farmers know they will be supported, they are more likely to report disease early. Only then can the government justify such a difficult decision.`,
questions:[
["Why do some experts advocate culling?",["It can stop a disease quickly","It is cheap for farmers","It improves meat quality","Everyone supports it"]],
["What might farmers do if compensation is late or too low?",["Hide sick animals","Buy more animals","Move to the city","Vaccinate more often"]],
["What does the writer believe?",["Culling can work if compensation is fair and fast","Culling should never happen","Compensation is unnecessary","Only experts should decide"]]]},

{title:"Where Do New Diseases Come From?", text:`About three in every four new infectious diseases in humans come from animals. Scientists call the moment when a pathogen jumps from an animal to a person a spillover.

Many viruses live quietly in a reservoir species, such as bats or wild birds, without making them sick. When the virus finds a new host with no immunity, such as a pig or a human, it can cause serious disease. Young, old and malnourished individuals are usually the most susceptible.

Some diseases are endemic, meaning they are always present in a region, like rabies in parts of Asia. Others appear suddenly and spread widely as an epidemic. If an epidemic crosses many countries, it becomes a pandemic, as we saw with COVID-19.

Early detection is difficult because of the incubation period, the time between infection and the first signs of illness. This is why diseases such as avian influenza are notifiable: vets and doctors must report every suspected case to the authorities immediately.`,
questions:[
["What is a spillover?",["When a pathogen jumps from an animal to a person","When a river floods","When a vaccine fails","When animals migrate"]],
["What is the difference between an epidemic and a pandemic?",["A pandemic crosses many countries","An epidemic is always mild","A pandemic affects only animals","There is no difference"]],
["Why must avian influenza cases be reported immediately?",["It is a notifiable disease","It is endemic everywhere","It has no incubation period","It is harmless"]]]},

{title:"Planning a Rabies Vaccination Campaign", text:`Every year, our district organises a campaign to vaccinate dogs against rabies. The goal is to reach at least 70 percent coverage, because this level creates herd immunity and protects the whole community, including puppies that are too young to be vaccinated.

Good planning starts with the cold chain. Vaccines must be kept between 2 and 8 degrees Celsius from the factory to the village. If they get too warm, their potency falls, and a dog may not be protected even though it received an injection.

The rabies vaccine we use is inactivated, but some other vaccines, such as those for Newcastle disease in chickens, are live attenuated vaccines. In both cases, the vaccine contains an antigen that trains the immune system to produce antibodies against the real virus.

Young dogs need a booster a few weeks after their first dose, and all dogs need a new dose every year. After last year's campaign, blood tests showed high antibody levels in most vaccinated dogs.`,
questions:[
["Why is 70 percent coverage important?",["It creates herd immunity","It is the legal price of vaccines","It makes vaccines cheaper","It stops dogs from barking"]],
["What happens if vaccines get too warm?",["Their potency falls","They become stronger","They change colour","Nothing happens"]],
["When do young dogs need a booster?",["A few weeks after their first dose","Only when they are old","Never","On the same day as the first dose"]]]},

{title:"From Farm to Laboratory", text:`When a vet suspects a bacterial infection, laboratory tests can help to confirm the diagnosis. But good results start on the farm.

Every specimen must be collected in a sterile tube and labelled with the date, the farm and the type of animal. Blood for antibody tests is spun in a centrifuge to separate the serum.

In the laboratory, technicians may grow bacteria in a culture for one or two days. They then use a Gram stain to see the shape and colour of the bacteria under the microscope. For viruses, they often use an ELISA assay or PCR. Each test needs the correct reagent, which must be stored at the right temperature.

No test is perfect. A test with high sensitivity finds almost every infected animal, but it may sometimes give a false positive, showing disease when there is none. That is why vets always combine laboratory results with the clinical signs they see on the farm.`,
questions:[
["What must be written on every specimen label?",["The date, the farm and the type of animal","The price of the test","The vet's age","Nothing"]],
["What is a Gram stain used for?",["To see the shape and colour of bacteria","To separate serum","To store reagents","To vaccinate animals"]],
["What is a false positive?",["A result showing disease when there is none","A test that finds every infected animal","A broken test tube","A test that is too expensive"]]]},

{title:"My First Surgery", text:`Last week I assisted with my first surgery: the castration of a young dog. I was nervous, but the surgeon explained every step.

First, the dog received mild sedation to keep it calm, and then it was placed under general anaesthesia. We clipped the hair and cleaned the skin carefully. The surgeon reminded me that aseptic technique is the most important way to prevent infection, so we wore sterile gloves and gowns.

She made a small incision and worked slowly to avoid haemorrhage. When a small blood vessel started to bleed, she tied it quickly. At the end, she closed the wound in two layers with an absorbable suture.

Postoperative care is just as important as the surgery itself. We gave pain relief and kept the dog warm while it woke up. Its recovery was smooth, and after ten days the owner said it was running and playing as normal.`,
questions:[
["What did the dog receive first?",["Mild sedation","A suture","Food","A vaccine"]],
["Why is aseptic technique important?",["It prevents infection","It makes surgery faster","It reduces the cost","It keeps the dog awake"]],
["What postoperative care did they give?",["Pain relief and warmth","No care at all","A second operation","A long walk"]]]},

{title:"Helping Cows Have Healthy Calves", text:`Good reproduction is the basis of a profitable dairy farm. Every cow should produce one calf per year, and a heifer should have her first calf at about two years old.

The first step is to detect oestrus. Cows in heat are restless and may try to mount other cows. On many farms, the farmer then calls a technician to perform artificial insemination, which allows the use of semen from high-quality bulls and improves the offspring.

Gestation in cattle lasts about nine months. During this time, good nutrition is essential, because poor feeding reduces fertility and can lead to weak calves.

Calving does not always go smoothly. Dystocia, or difficult birth, is common in young cows, and a vet may need to help. After the birth, the placenta should come out within twelve hours; if it does not, infection may follow. Diseases such as brucellosis can also cause abortion, so vaccination is important. Finally, a cow in early lactation needs extra energy to produce milk.`,
questions:[
["What is a sign of oestrus?",["Restlessness and mounting other cows","Loss of hair","Coughing","Sleeping more"]],
["What is one advantage of artificial insemination?",["It allows the use of high-quality bulls","It makes gestation shorter","It stops lactation","It prevents all diseases"]],
["What may happen if the placenta does not come out within twelve hours?",["Infection may follow","The calf dies immediately","Milk production doubles","Nothing"]]]},

{title:"Feeding Cattle in the Dry Season", text:`In the dry season, many cattle in Laos lose weight. The grass becomes old and tough, so it is less digestible and contains fewer nutrients.

Poor feeding over several months can lead to malnutrition. Thin animals are more likely to get sick, and their fertility falls. One common problem is mineral deficiency, especially of phosphorus, which can make cattle chew bones or soil.

Farmers can do several things. First, they can store good forage, such as dried grass or treated rice straw, before the dry season begins. Second, they can give a mineral supplement, often as a salt block that animals can lick. Third, animals that are working or producing milk may need some concentrate, such as rice bran or maize.

A balanced ration does not need to be expensive. Vets and farmers can plan it together using local feeds. Finally, a sudden loss of appetite is often the first sign of illness, so farmers should watch how much each animal eats every day.`,
questions:[
["Why do cattle lose weight in the dry season?",["The grass becomes tough and less nutritious","They walk too much","It is too cold","They drink too much water"]],
["Which sign may show phosphorus deficiency?",["Chewing bones or soil","Producing too much milk","Shiny hair","Very fast growth"]],
["What is often the first sign of illness?",["Loss of appetite","Weight gain","Loud mooing","Sleeping longer"]]]},

{title:"Following the Pork Value Chain", text:`In Laos, most pigs are raised by smallholder families who keep just two to five animals. For them, pigs are an important way out of poverty.

To understand how these farmers earn money, researchers studied the pork value chain, from the farm to the trader, the slaughterhouse and finally the market. They found that farmers received only a small share of the final revenue. Traders and sellers in the city earned much more.

One reason is poor market access. Many villages are far from good roads, so farmers must accept low prices from the few traders who visit. Disease is another problem: when an outbreak occurs, prices fall and markets close.

The study recommends simple, cost-effective solutions. Farmer groups can sell together to get better prices, and a small government subsidy for vaccines can prevent large losses. With these changes, pig raising can become more profitable. The researchers also call for investment in feed and training so that the system becomes sustainable in the long term.`,
questions:[
["How many pigs do most smallholder families keep?",["Two to five","Fifty","Five hundred","None"]],
["According to the study, who earns most of the revenue?",["Traders and city sellers","Farmers","Vets","The government"]],
["Which cost-effective solution does the study recommend?",["Farmers selling together in groups","Building a new airport","Stopping pig raising","Raising prices for consumers"]]]},

{title:"How an International Project Works", text:`Many animal health programmes in Southeast Asia are supported by international organisations. The Food and Agriculture Organization (FAO), for example, has a mandate to help countries improve food security and control animal diseases.

A typical project begins when a government asks for help. The organisation then works in partnership with the ministry to design a plan that follows national policy and international guideline documents, such as those produced by WOAH.

Funding usually comes from donor countries. With this money, the project may provide laboratory equipment and vaccines. However, the most important part is often capacity building: training local vets, laboratory staff and village workers so that they can continue the work after the project ends.

Collaboration between ministries is also essential. Agriculture, health and environment officers must share information, especially about zoonotic diseases. New regulation may be needed, for example to control the sale of antibiotics.

Finally, the project team must evaluate the results. Only by measuring what worked can they implement better programmes in the future.`,
questions:[
["According to the text, what is FAO's mandate?",["To help countries improve food security and control animal diseases","To sell vaccines for profit","To build roads","To train doctors only"]],
["What is often the most important part of a project?",["Capacity building","Buying vehicles","Holding celebrations","Printing newspapers"]],
["Why must the team evaluate the results?",["To learn what worked and improve future programmes","To spend the remaining money","To punish farmers","To close the ministry"]]]},

{title:"Talking to Farmers About Rabies", text:`Knowing the science is only half of a vet's job. The other half is communication.

Last month, our student team visited a village to raise awareness of rabies. At first, many people did not want to listen. One common misconception was that a dog bite is only dangerous if the dog looks sick. We had to explain that a dog can carry the virus before it shows any signs.

We quickly learned that long explanations did not work. Instead, we used pictures and short stories to convey the key messages. Our practical message was simple: we advised families to wash the wound with soap and water for fifteen minutes and go to the health centre the same day.

Some parents expressed concern about the cost of treatment. We were able to reassure them that the vaccine for people was free at the district hospital.

It took time to persuade families to bring their dogs for vaccination, but trust grew when they saw that we listened. At the end, we asked for feedback, and the villagers invited us to come back next year.`,
questions:[
["What misconception did the villagers have?",["A bite is only dangerous if the dog looks sick","Rabies only affects cats","Vaccines cause rabies","Washing wounds is harmful"]],
["What practical advice did the team give?",["Wash the wound for fifteen minutes and go to the health centre","Wait a week and see","Keep the dog locked inside","Put herbs on the wound"]],
["How did the team build trust?",["By listening to the villagers","By giving money","By speaking only English","By leaving quickly"]]]},

{title:"Livestock in a Changing Climate", text:`Climate change is already affecting farmers in Laos. The rainy season is becoming less predictable, with long periods of drought followed by sudden flooding.

These changes create new health problems for animals. Heat stress reduces feed intake and milk production, and it can even kill pigs and poultry kept in hot, crowded houses. Flooding spreads diseases such as leptospirosis and contaminates drinking water with pollution from farms and villages.

Many diseases also follow a seasonal pattern. Warmer and wetter conditions help mosquitoes and ticks survive longer, so vector-borne diseases may appear in new areas.

At the same time, livestock contribute to the problem. Cattle produce methane, and poor manure management increases greenhouse gas emissions. Overgrazing also causes land degradation, leaving less grass for the future.

The good news is that farmers can adapt. Local breeds tolerate heat better, trees provide shade, and stored fodder helps animals survive the dry months. These steps build the resilience of farms, so that they can recover more quickly from shocks.`,
questions:[
["How is the rainy season changing?",["It is becoming less predictable","It is disappearing completely","It always lasts longer","It happens twice a month"]],
["How do livestock contribute to climate change?",["Cattle produce methane and manure increases emissions","They drink too much water","They eat mosquitoes","They cause earthquakes"]],
["What is one way farmers can adapt?",["Keeping local breeds that tolerate heat","Keeping more animals in hot houses","Stopping vaccination","Cutting down trees"]]]},

{title:"Reading the Results of a Survey", text:`Last year, our faculty carried out a survey of 300 dog-owning households in Vientiane Province. The aim was to estimate how many dogs had been vaccinated against rabies.

We used a computer program to analyse the data. The average number of dogs per household was 2.4, but the median was 2, because a few families kept many dogs. One household, with 25 dogs, was an outlier, and we checked carefully that it was not a recording mistake.

Overall, 46 percent of dogs had been vaccinated, with a 95 percent confidence interval of 40 to 52 percent. This means that the true percentage in the whole province is probably within this range.

Compared with a similar survey five years ago, there is an upward trend in vaccination. However, we must interpret this result with care, because the two surveys used different methods. The next step is to repeat the survey every two years using the same questions.`,
questions:[
["Why was the median lower than the average?",["A few families kept many dogs","The survey was too small","Nobody owned dogs","The computer made an error"]],
["What percentage of dogs had been vaccinated?",["46 percent","25 percent","95 percent","2.4 percent"]],
["Why must the upward trend be interpreted with care?",["The two surveys used different methods","The dogs were too old","The confidence interval was zero","The data were lost"]]]},

{title:"An Email to a Project Coordinator", text:`Dear Ms Chanthavong,

I am writing regarding the training workshop on rabies control that was planned for 10 November.

As we discussed at last week's meeting, several district vets will be busy with the vaccination campaign on that date. I would therefore like to propose that we postpone the workshop to 24 November. Please let me know if you are available on that day.

I have attached a draft agenda for the workshop. Could you also clarify how many participants each province can send? We need this information to book the venue before the deadline on Friday.

I have also attached the minutes of last week's meeting for your records. I will follow up with the district offices tomorrow and send you an updated list of participants.

Thank you for your support.

Best regards,
Bounmy`,
questions:[
["Why does the writer want to postpone the workshop?",["District vets will be busy with the vaccination campaign","The venue is closed","The coordinator is sick","There is no agenda yet"]],
["What has the writer attached to the email?",["A draft agenda and the minutes of the last meeting","A list of vaccines","An invoice","A map"]],
["What will the writer do tomorrow?",["Follow up with the district offices","Book a flight","Cancel the campaign","Write new minutes"]]]},

{title:"From Farm to Fork", text:`Veterinarians play an important role in food safety, even though many people do not realise it.

At the slaughterhouse, every animal should be checked before and after slaughter. During meat inspection, vets look for signs of disease, such as abscesses or swollen organs, and remove unsafe meat from the food chain.

Good hygiene is essential at every step. Dirty knives, cutting boards and hands can cause cross-contamination, spreading bacteria such as Salmonella from raw meat to cooked food. These foodborne infections can cause serious illness, especially in children and older people.

Temperature is also important. Meat that is not kept cold suffers from rapid spoilage, and its shelf life becomes much shorter.

Another concern is drug residue. If farmers sell animals before the withdrawal period ends, antibiotics can remain in the meat. To prevent this, many countries improve traceability by giving animals ear tags, so that every carcass can be linked back to its farm.`,
questions:[
["What do vets look for during meat inspection?",["Signs of disease such as abscesses","The colour of the truck","Only the farmer's name","The price of the meat"]],
["How can cross-contamination happen?",["Through dirty knives, boards and hands","By cooking meat well","By keeping meat cold","By washing hands"]],
["How do ear tags improve traceability?",["They link each carcass back to its farm","They make meat last longer","They kill bacteria","They reduce the price"]]]},

{title:"A Post-Mortem Examination", text:`When a pig died suddenly on a farm near Pakse, the farmer asked us to find out why. We carried out a post-mortem examination the same afternoon.

We started with the outside of the body. The skin on the ears and belly was dark red, and one lymph node under the jaw was swollen. We then opened the thorax. The lungs were heavy and full of fluid, and there was foam in the trachea.

Next, we examined the abdomen. The spleen was very large and dark, almost black, and the kidney surface showed small red spots. There were also areas of bleeding in the intestine, while the liver looked mostly normal.

These signs strongly suggested African swine fever, so we sent samples to the laboratory and reported the case immediately.

Pigs have a simple stomach, unlike cattle, which have a large rumen for digesting grass. In a dairy cow, a post-mortem would also include the udder, to look for signs of mastitis.`,
questions:[
["What did the team find in the trachea?",["Foam","Worms","Blood clots","Grass"]],
["What did the spleen look like?",["Very large and dark","Small and pale","Completely normal","It was missing"]],
["What did they do after finding these signs?",["Sent samples and reported the case immediately","Sold the other pigs","Buried the pig without reporting","Treated the remaining pigs with antibiotics"]]]},

{title:"The Story of Rinderpest", text:`Rinderpest, or cattle plague, was once one of the most feared animal diseases in the world. It could spread quickly through herds and affect cattle, buffalo and many wild animals. In some outbreaks, more than 90 percent of infected animals died, and few were able to recover.

For centuries, the disease caused famine in Africa and Asia, because farmers lost the animals they needed for ploughing and food.

In the twentieth century, scientists developed an effective vaccine that could prevent infection. But vaccines alone were not enough. Teams also had to detect every remaining case, even in remote areas. Where the virus continued to persist in wild animals, surveillance became even more important.

After a long global campaign, rinderpest was declared eradicated in 2011. It was only the second disease, after smallpox, that humans have been able to eradicate.

Today, new diseases continue to emerge, and problems such as poverty and conflict can trigger new outbreaks or worsen existing ones. The lessons of rinderpest remind us what is possible when countries work together.`,
questions:[
["Why did rinderpest cause famine?",["Farmers lost the animals they needed for ploughing and food","It destroyed rice fields directly","It infected humans","It caused floods"]],
["In which year was rinderpest declared eradicated?",["2011","1911","2001","2021"]],
["Which was the first disease that humans eradicated?",["Smallpox","Rabies","Rinderpest","Malaria"]]]},

{title:"My Personal Statement", text:`I am a final-year veterinary student from Laos, and I am highly motivated to work in international animal health.

During my clinical training, I have learned that good vets need more than technical skills. They must be empathetic, because farmers often feel worried or afraid when their animals are sick. I always try to listen carefully and explain things in simple language.

I am also meticulous in my work. In the laboratory, I keep detailed records of every sample, and my supervisor describes me as reliable and well organised.

I enjoy working in teams. As part of a collaborative student project on rabies, I took the initiative to design pictures for village education sessions. I also learned to be adaptable, because plans often changed when roads were flooded or villagers were busy in the fields.

I believe in a proactive approach to disease control: it is better to prevent problems than to react to them. I am committed to using my skills to improve the health of animals and the livelihoods of rural families.`,
questions:[
["According to the writer, why must vets be empathetic?",["Farmers often feel worried when their animals are sick","It makes surgery faster","It is required by law","Animals prefer quiet vets"]],
["What initiative did the writer take in the rabies project?",["Designed pictures for education sessions","Bought vaccines","Wrote a new law","Built a clinic"]],
["Why did the writer have to be adaptable?",["Plans changed when roads flooded or villagers were busy","The supervisor was strict","The laboratory closed","There was no internet"]]]},

{title:"How Is Food Production Changing in Asia?", text:`Over the past thirty years, the way people eat in Asia has changed dramatically.

One major reason is population growth. More people need more food, and rising incomes mean that families can buy more meat, eggs and milk. Urbanisation is another factor. As people move to cities, they buy more processed food, and the consumption of pork and chicken rises.

This growing demand has changed livestock farming. In the past, most animals were raised in rural villages. Today, large commercial farms produce a growing share of meat, especially near big cities.

Globalisation also plays a role. Feed, animals and meat are traded across borders, which makes food more affordable but also allows diseases to travel faster.

At the same time, the migration of young people to cities leaves fewer workers in the countryside. Many remote villages still have poor infrastructure, such as roads and electricity, and limited access to veterinary services. Finding a balance between growth and safety is one of the biggest challenges for the future.`,
questions:[
["Why is the consumption of pork and chicken rising?",["People move to cities and incomes rise","Rice is disappearing","Doctors recommend it","Pigs are free"]],
["What negative effect of globalisation does the text mention?",["Diseases can travel faster","Food becomes more expensive","Farms disappear","Cities get smaller"]],
["What problem do many remote villages still have?",["Poor infrastructure and limited access to vets","Too many vets","Too much electricity","No animals at all"]]]},

{title:"Why One Health Matters", text:`One Health is an approach that recognises the close links between the health of people, animals and the environment. It is based on a simple principle: we cannot protect one without protecting the others.

There is strong evidence to support this idea. Most new human diseases come from animals, and antimicrobial resistance is a global issue that affects hospitals and farms alike. Environmental factors, such as deforestation and flooding, also have a direct impact on the spread of disease.

Many countries now use One Health as a framework for planning. Instead of each ministry working alone, doctors, vets and environmental scientists share data and respond together. For example, many countries have adopted a national strategy to end human deaths from rabies by 2030, which involves both the health and agriculture sectors.

Veterinarians play a key role in this system. By vaccinating animals, monitoring disease and advising farmers, they protect human health as well. No single method can solve every problem, but working together gives us the best chance of success.`,
questions:[
["What is the basic principle of One Health?",["We cannot protect one without protecting the others","Animals are more important than people","Only doctors can stop diseases","The environment does not matter"]],
["Which environmental factors does the text mention?",["Deforestation and flooding","Television and radio","Traffic lights","School holidays"]],
["According to the text, how do vets protect human health?",["By vaccinating animals, monitoring disease and advising farmers","By treating patients in hospitals","By building roads","By selling food"]]]}
];
