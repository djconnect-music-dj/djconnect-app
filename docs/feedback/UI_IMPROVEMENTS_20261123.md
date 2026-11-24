# Verbeteringen Apple-clients — 23 november 2026

Werkbranch: `codex/ui-verbeteringen-20261123`.
Startpunt: Apple-main `2c26d5adf2a2c3164219b0a68237e9c0f472ca26`.

Dit is de verzamellijst voor de door de gebruiker gemelde verbeteringen.
Registratie is geen bewijs van implementatie of herstel op een apparaat.

## 1. Gloedrand Start DJ-sessie

- Verzoek: geef de knop **Start DJ-sessie** een witte, geanimeerde gloedrand,
  zoals aangegeven op de aangeleverde foto.
- Behoud de bestaande knoptekst, werking en vorm. Respecteer de instelling
  voor minder beweging met een rustige, statische rand.
- Status: geregistreerd; nog niet geïmplementeerd.

## 2. Watch: ingesproken afspeelverzoek zonder DJ-sessie

### Gemeld gedrag

- Omgeving: HA dev; de foutmelding verschijnt op de Watch.
- Voorval: volgens de gebruiker meer dan een week vóór deze melding.
- Geen actieve DJ-sessie; spreek in Ask DJ **speel London Grammar** in.
- Volgens de gebruiker wordt de muziek/wachtrij afgespeeld, waarna de Watch
  meldt dat Ask DJ niet beschikbaar is.
- Aanvullende verwachting: zonder gekozen speaker eerst een popup om een
  speaker te kiezen.

### Gewenst gedrag en controle

1. Controleer dit scenario op de actuele geïnstalleerde Watch-, iPhone- en
   HA-dev-versies; leg die versies bij het resultaat vast.
2. Ask DJ blijft beschikbaar zonder een DJ-sessie te starten.
3. Als een uitvoerkeuze nodig is, toon de door Core geleverde speakerkeuzes
   als popup. Start de gevraagde muziek pas na de expliciete keuze. Annuleren
   start geen muziek; de Apple-client verzint geen uitvoer of muziekintentie.
4. Toon na een bevestigd geslaagd verzoek het ontvangen antwoord. Een fout
   bij aanvullende geschiedenis- of statusverversing mag dat bevestigde
   resultaat niet veranderen in een mislukt afspeelverzoek.
5. Bij onbekende aflevering: controleer uitsluitend de oorspronkelijke
   verzoekidentiteit; stuur het afspeelverzoek niet automatisch opnieuw.
6. Controleer ook een al gekozen speaker, geannuleerde speakerkeuze,
   mislukte uitvoerwissel en een verbroken iPhone-verbinding.

### Onderzoek tot nu toe

- De huidige bronroute loopt via de iPhone-companion en een profielgebonden
  gesprek; een lege sessie-ID is daarvoor een bestaande context.
- De actuele Watch-spraakweergave bevat geen automatische speakerpopup na
  een antwoord. Deze weergave moet de bestaande Core-acties blijven gebruiken.
- De ingesproken melding is niet in de beschikbare recente HA-dev logs
  teruggevonden. Die logs bevestigen of weerleggen dit oudere voorval niet.
- De oorzaak van de gemelde fout ná afspelen is nog niet vastgesteld.
- Status: geregistreerd en bronroute onderzocht; actuele reproductie,
  eventuele reparatie en apparaatcontrole staan open.

## 3. Nieuw: Horizon DJ-moment — Up next

### Verzoek

- Toon binnen de actieve sessie tijdelijk een previewcard wanneer het huidige
  nummer bijna afgelopen is.
- De kaart toont het artwork en de titel van het volgende nummer, met een
  korte tekstuele introductie **van je DJ**.
- Dit heet een **Horizon DJ-moment**.
- De tekstuele vooruitblik komt naast de bestaande muziekaankondiging en
  vervangt of onderdrukt die niet. De kaart start zelf geen gesproken intro.

### Randvoorwaarden voor uitwerking

- Core blijft eigenaar van het volgende nummer, de DJ-tekst en de geldigheid
  van het moment; Apple rendert de aangeboden preview.
- Gebruik de actuele afspeelvolgorde. Trek een achterhaalde preview in of
  vervang die als het volgende nummer verandert. Verzin geen volgend nummer
  wanneer dat nog onbekend is.
- De kaart verdwijnt zodra de vooruitblik niet meer geldig is, bijvoorbeeld
  na de nummerwisseling of bij het beëindigen van de sessie.
- Werk het verschijnmoment bij de resterende speeltijd en de tijdelijke
  weergaveduur uit; er is nog geen aantal seconden afgesproken.
- Bij een benodigde contractuitbreiding eerst de Core-specificatie en
  afstemming bijwerken, vóór de Apple-implementatie.
- Status: geregistreerd; ontwerp, implementatie en controles staan open.

## 4. Track Insight werkt niet meer goed

- Gebruikersmelding: **Track Insight doet het niet (goed meer)**.
- Apparaat, omgeving (HA dev of productie), concrete handeling en zichtbaar
  resultaat zijn nog niet bekend; verduidelijking is gevraagd.
- Leg bij reproductie vast welk nummer wordt onderzocht en of de fout zit
  in beschikbaarheid, ophalen, weergave of inhoud. Controleer dat het inzicht
  bij het bedoelde nummer hoort, ook na een nummerwisseling.
- Inhoud en onderbouwing blijven backend-eigendom; de Apple-client verzint
  geen analyse als vervanging voor een ontbrekend of mislukt antwoord.
- Status: geregistreerd; oorzaak en herstel nog niet vastgesteld.

## 5. Ask DJ: herhaalde verduidelijking bij leeftijdsvraag Novastar

### Zichtbaar op de aangeleverde screenshot

- De gebruiker schrijft **Band novastar**.
- Ask DJ vraagt: **Bedoel je hoe lang de band Novastar bestaat, of de
  leeftijd van een specifieke muzikant?**
- De gebruiker antwoordt **Leeftijd**.
- Ask DJ stelt opnieuw exact dezelfde vraag. De gebruiker meldt dat deze
  vervolgvraag blijft terugkomen.
- De voorafgaande oorspronkelijke leeftijdsvraag is niet volledig zichtbaar;
  exacte appversie en HA-omgeving zijn nog niet vastgesteld. Niet gelijkstellen
  aan het afzonderlijke Track Insight-probleem.

### Gewenst gedrag en controle

- Gebruik de bestaande gesprekscontext: **Leeftijd** is een antwoord op de
  zojuist gestelde verduidelijkingsvraag en geen losse nieuwe vraag.
- Als de bedoelde persoon eenduidig vaststaat, beantwoord diens leeftijd op
  basis van onderbouwde informatie. Als die persoon nog ontbreekt, vraag
  gericht **welke muzikant** de gebruiker bedoelt. Herhaal niet de reeds
  beantwoorde keuze tussen bestaansduur en leeftijd.
- Controleer de hele gespreksketen, inclusief een vervolg met een persoonsnaam
  en het alternatief waarbij de gebruiker juist de bestaansduur bedoelt.
- Interpretatie, behoud van de gesprekscontext en feitelijke onderbouwing
  blijven Core-eigendom; voeg geen lokale Novastar- of trefwoorduitzondering
  aan de Apple-client toe.
- Status: geregistreerd met screenshot als gedragsbewijs; oorzaak, reparatie
  en controle op de huidige versie staan open.

## 6. VibeCast UI: Horizon zonder scrollbar en dubbele huidige track

- Verzoek op de aangeleverde foto: **Haal scrollbar weg bij Horizon.
  Horizon toont onnodig huidige track nog dubbel.**
- De foto toont bovenaan de huidige track **Children — Armin van Buuren**
  en daarnaast in het Horizon-paneel **De komende minuten** opnieuw
  **Nu speelt: Children — Armin van Buuren**.
- Verwijder de zichtbare scrollbar bij Horizon. Controleer dat de inhoud
  daarbij leesbaar en bereikbaar blijft op de ondersteunde schermformaten.
- Verwijder de overbodige herhaling van de huidige track uit Horizon;
  de bestaande hoofdweergave van het huidige nummer blijft behouden.
- Horizon richt zich op de vooruitblik. Dit UI-verzoek staat naast het
  nieuwe tijdelijke **Horizon DJ-moment — Up next** uit punt 3.
- Dit betreft de VibeCast-schermweergave; bepaal bij uitvoering de eigenaar
  van de renderer en wijzig niet uitsluitend de Apple-client.
- Status: geregistreerd met foto; nog niet geïmplementeerd of gecontroleerd.

## 7. VibeCast bug: track-art verdwijnt en verschijnt periodiek

- Gebruikersmelding: de track-art verdwijnt en komt iedere zoveel seconden
  weer terug. Het exacte interval en de omgeving zijn nog niet vastgesteld.
- Gewenst gedrag: het artwork blijft stabiel zichtbaar zolang hetzelfde
  nummer speelt en de afbeelding geldig en beschikbaar is. Een gewone
  statusverversing mag de afbeelding niet telkens laten verdwijnen.
- Onderzoek bij reproductie of het probleem samenvalt met statusupdates,
  opnieuw laden van de afbeelding, verlopen afbeeldingsverwijzingen of het
  opnieuw opbouwen van de weergave. Dit zijn onderzoekspunten, geen bewezen
  oorzaken.
- Controleer ook een echte nummerwisseling en een ontbrekende of mislukte
  afbeelding: geen flikkering, onnodig leeg beeld of achtergebleven artwork
  van het vorige nummer. Respecteer de geldigheid van de afbeeldingsbron.
- Status: geregistreerd; reproductie, oorzaak en reparatie staan open.

## 8. VibeCast bug: artwork ontbreekt bij muziekbijdragen

- Gebruikersmelding: muziekbijdragen in VibeCast missen artwork.
- Toon het bijbehorende artwork wanneer de backend een geldige afbeelding
  voor de bijdrage levert. Controleer zowel de levering als de weergave;
  de oorzaak is nog niet vastgesteld.
- Gebruik bij ontbrekende afbeeldingen een passende fallback, zonder
  artwork van een andere bijdrage of het huidige nummer over te nemen.
- Status: geregistreerd; reproductie, oorzaak en reparatie staan open.

## 9. VibeCast: sessieduur en resterende tijd in de deelsheet

- Verzoek: verleng de VibeCast-sessieduur van de door de gebruiker genoemde
  twee uur naar vier uur, of laat de gebruiker de duur instellen in de
  VibeCast-deelsheet. De huidige limiet is nog niet in de bron geverifieerd.
- Dit zijn alternatieven; de keuze tussen een vaste duur van vier uur en
  een instelbare duur staat nog open.
- Toon op Apple-apparaten in de VibeCast-deelsheet de resterende tijd van
  de gedeelde VibeCast-sessie.
- Core blijft eigenaar van de vervaltijd en eventuele verlenging. Openen
  van de deelsheet of lokaal aftellen verlengt de sessie niet vanzelf.
- Controleer bij uitvoering dat de getoonde resterende tijd overeenkomt met
  de werkelijke geldigheid, ook bij heropenen, verlopen en een wijziging van
  de duur. Maak onderscheid tussen VibeCast-deelduur en DJ-sessieduur.
- Status: geregistreerd; duurkeuze, contractcontrole, implementatie en
  apparaatcontrole staan open.

## 10. VibeCast: DJ-avatar als pop-up en blijvend klein in beeld

- Verzoek: toon de DJ-avatar kort als pop-up bij sessiewijzigingen.
- Toon daarnaast een kleine DJ-avatar op een vaste plek in de
  VibeCast-weergave, ook wanneer er geen pop-up is.
- Gebruik de bestaande DJ-avatar en de bevestigde sessiecontext. Een gewone
  statusverversing mag de pop-up niet telkens opnieuw activeren.
- Werk de precieze sessiewijzigingen die een pop-up oproepen, de plek van de
  kleine avatar en de tijdelijke weergaveduur uit. Die details zijn nog
  niet afgesproken.
- Controleer dat de avatar belangrijke inhoud en bediening niet bedekt,
  ook op kleinere VibeCast-schermen.
- Status: geregistreerd; ontwerp, implementatie en controles staan open.

## 11. iPhone: Google Cast-route nog niet aangesloten

- Gebruikersmelding: de Google Cast-route is op de iPhone nog niet aangesloten.
- Onderzoek welke aansluiting ontbreekt in de bestaande Cast-route en sluit
  die aan op de bedoelde VibeCast-gebruikersflow.
- Behoud het onderscheid tussen een native Google Cast-sessie en het openen
  van een VibeCast-webscherm; een werkende webroute bewijst geen werkende Cast-route.
- Controleer de volledige route op een fysieke iPhone met een echte
  Cast-ontvanger, inclusief kiezen, verbinden, stoppen en opnieuw verbinden.
- Status: geregistreerd; ontbrekende aansluiting, implementatie en
  apparaatcontrole staan open.

## 12. iPhone: VibeCast-afstandsbediening met Vibescape/Flow-keuze

- Verzoek: maak op de iPhone een VibeCast-remotecontrolscherm.
- Laat de gebruiker daar het verbonden VibeCast-scherm omschakelen tussen
  **Vibescape** en **Flow**.
- Toon de bevestigde weergavestand van het bediende scherm. Een lokale
  selectie zonder bevestiging geldt niet als geslaagde omschakeling.
- Gebruik de bestaande bevoegde bedieningsroute; werk ontbrekende
  backendcontracten eerst met Core af. De keuze verandert de VibeCast-weergave,
  niet vanzelf de muziekweergave of DJ-sessie.
- Controleer beide omschakelrichtingen, de aanvankelijke stand, heropenen
  van de afstandsbediening en een verbroken verbinding.
- De plek van dit nieuwe scherm in de iPhone-navigatie en eventuele overige
  afstandsbedieningsfuncties zijn nog niet afgesproken.
- Status: geregistreerd; ontwerp, contractcontrole, implementatie en
  apparaatcontrole staan open.

## 13. VibeCast: sessietaal overnemen van de app

- Verzoek: laat de VibeCast-sessie de ingestelde taal van de app overnemen.
- Gebruik bij het starten of delen de daadwerkelijk gekozen app-taal,
  inclusief een expliciete taalkeuze die afwijkt van de systeemtaal.
- Geef de taal door via het backendcontract zodat de sessietaal ook op het
  verbonden VibeCast-scherm wordt toegepast; alleen de deelsheet vertalen
  voldoet niet aan dit verzoek.
- Werk nog uit of een wijziging van de app-taal ook een reeds actieve
  VibeCast-sessie moet wijzigen en welke bedienende app daarbij leidend is.
- Controleer de ondersteunde talen en een verschil tussen app- en systeemtaal.
- Status: geregistreerd; contractcontrole, implementatie en controles staan open.

## 14. VibeCast: Spotify-logo bij bijdragen herstellen

- Verzoek: vervang bij VibeCast-bijdragen de zichtbare **Spotify policy**-link
  weer door het **Spotify-logo**.
- Gebruik het bestaande Spotify-logo uit de gedeelde vormgeving. Controleer
  bij uitvoering de bijbehorende linkbestemming en toegankelijke naam.
- Status: geregistreerd; implementatie en visuele controle staan open.

## 15. VibeCast: waargenomen playback ook als items tonen

- Verzoek: toon waargenomen playback ook als items in VibeCast.
- Gebruik de door Core bevestigde afspeelwaarnemingen; een wachtrij-item of
  afspeelverzoek is op zichzelf geen bewijs dat het nummer heeft gespeeld.
- Voorkom dat periodieke statusupdates voor hetzelfde afspeelgebeuren steeds
  nieuwe items maken. Een daadwerkelijk nieuwe afspeelbeurt kan wel een
  afzonderlijk item zijn.
- Werk de plek en vorm van deze items binnen de VibeCast-weergave uit.
- Status: geregistreerd; ontwerp, contractcontrole, implementatie en
  controles staan open.

## 16. VibeCast-sessieflow: groot lettertype voor de hele lijst

- Gebruikersmelding: het lettertype van de onderste items in de sessieflow
  is te klein.
- Verzoek: gebruik een groot, goed leesbaar lettertype in de hele flowlijst,
  ook voor items onderaan. Verklein de tekst niet op basis van de positie
  van het item in de lijst.
- Controleer de leesbaarheid op het VibeCast-scherm, inclusief langere
  teksten en tekstomloop, zonder de onderste items opnieuw kleiner te maken.
- Status: geregistreerd; implementatie en visuele controle staan open.

## 17. VibeCast: content vloeiend over de onderste schermrand

- Verzoek: laat content aan de onderrand visueel het scherm binnen- en
  uitrollen, in plaats van deze abrupt achter de onderste statusbalk af
  te kappen.
- Stem de beweging, zichtbare schermrand en plaatsing van de statusbalk op
  elkaar af, zodat de overgang vloeiend oogt en de status leesbaar blijft.
- Controleer dit met de grotere tekst uit punt 16, langere items en
  verschillende schermformaten. Respecteer de instelling voor minder beweging.
- Status: geregistreerd; implementatie en visuele controle staan open.

## 18. VibeCast Horizon: direct tekst, zonder subkopjes

- Verzoek: toon in Horizon meteen de inhoudelijke tekst, zonder subkopjes
  zoals **De komende minuten**.
- Combineer dit met punt 6: geen overbodige herhaling van de huidige track
  en geen zichtbare scrollbar bij Horizon.
- Status: geregistreerd; implementatie en visuele controle staan open.

## 19. VibeCast Horizon: rustige, stabiele inhoud

- Gebruikersmelding: Horizon-data knippert te vaak, verdwijnt kort of
  verandert onnodig. Dit maakt het scherm onrustig.
- Houd geldige Horizon-inhoud zichtbaar tijdens gewone verversingen.
  Ongewijzigde gegevens mogen geen leeg tussenscherm, knippering of nieuwe
  overgang veroorzaken.
- Wijzig de zichtbare inhoud alleen wanneer daar een inhoudelijke reden
  voor is; onderzoek ook waarom de gegevens zelf zo vaak veranderen.
- Verwijder of vervang achterhaalde of ingetrokken inhoud wel volgens de
  geldigheid van de bron. Stabiliteit mag geen verouderde vooruitblik tonen.
- Controleer meerdere verversingscycli en echte wijzigingen van de sessie
  of vooruitblik. Combineer dit met de vereenvoudiging uit punten 6 en 18.
- Status: geregistreerd; oorzaak, implementatie en visuele controle staan open.

## 20. VibeCast Horizon: zin over mogelijke wijzigingen verwijderen

- Verzoek: verwijder de zin **Muziek en bijdragen kunnen wijzigen** uit Horizon.
- Neem dit mee bij het vereenvoudigen van Horizon uit punten 6 en 18.
- Status: geregistreerd; implementatie en visuele controle staan open.

## 21. Apple-apps en VibeCast: ademende animatie voor track-art

- Verzoek: geef de track-art in de Apple-apps en VibeCast een ademende animatie.
- Gebruik een rustige, subtiele en vloeiende beweging; werk tempo en
  amplitude bij de vormgeving uit.
- Het artwork blijft zichtbaar en herkenbaar. De animatie mag geen knippering,
  leeg beeld, opnieuw laden van de afbeelding of verschuivende omliggende
  inhoud veroorzaken. Neem de VibeCast-bug uit punt 7 hierin mee.
- Respecteer de instelling voor minder beweging met stilstaand artwork en
  stop animatiewerk wanneer de betreffende weergave niet zichtbaar is.
- Controleer de betreffende Apple-platforms en VibeCast, inclusief een echte
  nummerwisseling en ontbrekend artwork.
- Status: geregistreerd; vormgeving, implementatie en visuele controle staan open.

## 22. VibeCast: gastmodus-QR rechtsboven bij statusicoontjes

- Verzoek: voeg rechtsboven, bij de statusicoontjes, de QR-code voor
  **guest mode / gastmodus** toe.
- Tijdens een actieve sessie roteert de join-QR elke twee minuten subtiel.
  Gebruik de geldige gastuitnodiging voor die sessie; gewone statusverversingen
  veroorzaken geen extra rotatie of knippering.
- V1 leidt naar de DJConnect-app, met TestFlight/App Store als installatieroute.
  Bij een geïnstalleerde app opent de uitnodiging de bevestiging om de sessie
  als gast te joinen, zonder pincode. Zie de uitwerking en open linkvragen in
  punt 23. Een responsieve gastwebsite is kandidaat voor v2.
- Werk de presentatie op die plek uit met behoud van scanbaarheid en
  leesbare statusicoontjes. Controleer dit op de ondersteunde schermformaten.
- Controleer ook uitgeschakelde gastmodus en een verlopen of ingetrokken
  uitnodiging; toon dan geen ongeldige toegangscode als bruikbaar.
- Status: geregistreerd; vormgeving, contractcontrole, implementatie en
  scancontrole staan open.

## 23. Gastmodus: tijdelijk deelnemen aan een VibeCast-sessie in de app

### Productrichting en versies

- Primaire route voor v1: gasten gebruiken de DJConnect-app. Voeg op het
  sessiestart-/demostartscherm **Join session (guest mode)** toe.
- De tv-QR uit punt 22 nodigt uit voor de actieve sessie. Met de app al
  geïnstalleerd opent die de app en een deelnamebevestiging; er is geen pincode.
- Zonder app verwijst de route naar TestFlight of de App Store, afhankelijk
  van de distributie. Werk uit hoe de juiste sessie na installatie wordt
  hervat; een gewone winkellink draagt die context niet vanzelf over.
- De eerst genoemde responsieve HTML-pagina, met dezelfde actieve inhoud
  als de tv en gastinteractie, schuift naar kandidaat-v2, onder meer voor
  Android-gebruikers. Voor v1 staat de native gastmodus voorop.
- De aanvankelijk genoemde reacties op bijdragen zijn vervangen door
  emoties bij het **huidige nummer**; bouw geen bijdrage-reacties voor v1.

### Toegang, verbinding en einde

- Toon alleen de publiek voor gasten vrijgegeven, beperkte bijdragen en
  sessieflow van de joined sessie; geen privé-inhoud van de host.
- De QR roteert elke twee minuten. Geen pincode betekent deelname via een
  geldige uitnodiging met expliciete bevestiging, niet onbeperkte toegang tot
  willekeurige sessies. Core bepaalt toelating, geldigheid en intrekking.
- QR-rotatie verbreekt niet op zichzelf het lidmaatschap van reeds
  bevestigde gasten. Leg de join- en deelnemerslevensduur afzonderlijk vast.
- Het verbindingsicoon geeft de werkelijke verbinding met de joined
  gastensessie weer; het mag geen hostkoppeling of eigen sessie suggereren.
- De stopknop in de werkbalk betekent **Leave joined session** en stopt
  nooit de sessie of muziek van de host.
- Na disconnect is de joined sessiedata op het apparaat weg, inclusief de
  tijdelijke eigen gespreksflow. Geen gastgeschiedenis bewaren of later
  opnieuw tonen. Werk de exacte grens tussen korte transportonderbreking en
  beëindigde deelname nog uit; geen blijvende offline gastcache.

### Verzoeken, vragen en bevoegdheden

- De Ask DJ-balk binnen de joined sessie accepteert verzoeknummers en
  muziekinformatievragen. Vragen en antwoorden komen alleen in de tijdelijke
  eigen sessieflow van deze gast op dit apparaat, niet in de publieke flow
  of een andere gast zijn gesprek.
- Geen playbackbediening via Ask DJ: bijvoorbeeld pauze, skip, volume of
  uitvoer wisselen. Een verzoeknummer is een gastverzoek, geen directe
  bevoegdheid om de hostplayback of wachtrij te wijzigen.
- Geen sessiekenmerken wijzigen. Werkbalkitems mogen wel voor alleen-lezen
  inzage worden geopend.
- Handhaaf dit in Core voor alle gastacties, ook bij vrije tekst in Ask DJ;
  alleen verborgen of uitgeschakelde knoppen zijn onvoldoende.
- Muziekvragen blijven backend-eigendom, met alleen de toegestane publieke
  sessiecontext. Gebruik geen privégeschiedenis of Music DNA van de host.
- Leg het ontvangen van een gastverzoek door de host en de eventuele
  acceptatie-/wachtrijroute nog vast; de gebruiker heeft hier geen beleid
  voor automatische plaatsing of moderatie afgesproken.

### Beschikbare en lege schermen

- Horizon van de joined sessie is zichtbaar.
- Vibescape is beschikbaar en volgt de sessie-instellingen van de host;
  alleen dynamiek mag de gast wijzigen. Werk nog uit of dat uitsluitend
  de eigen weergave betreft; geen impliciete wijziging van het tv-scherm.
- Wachtrij en Playlists blijven bewust leeg in gastmodus.
- Het losse Ask DJ-scherm buiten de sessie blijft leeg.
- **Voor jou** is uitgeschakeld.
- Geen invloed van gastgebruik op Music DNA of Ontdekt. Eigen gekoppelde
  inhoud mag niet onder de gastidentiteit zichtbaar worden of wijzigen.
- Track Insight via de hostserver is nog een open productkeuze; niet als
  ingeschakelde v1-functionaliteit beschouwen zonder expliciete keuze en
  beperkte gastbevoegdheid.

### Emoties bij het huidige nummer

- Toon op de hoek van de huidige-songafbeelding één emoticonbediening.
  Na een tik opent een werkbalk met vijf emoticoniconen; de exacte set
  moet nog worden gekozen.
- De gekozen emotie beantwoordt **wat vind je van de huidige muziek?**.
  Koppel die aan het bedoelde huidige nummer, niet aan een DJ-bijdrage.
- Laat de emoties live als een laag over de tv-weergave vliegen.
- Controleer de nummeridentiteit bij verzenden en ontvangen, zodat een
  reactie rond een nummerwisseling niet bij het verkeerde nummer belandt.
- Gastemoties zijn geen Music DNA-feedback of duurzame smaakopbouw.

### Spraak en AI: v1-keuzes bevestigd

- De gebruiker vraagt of TTS voor DJ-bijdragen en STT de sessie-instellingen
  kunnen volgen en of dat wenselijk is qua tokengebruik.
- De gebruiker heeft bevestigd: v1 alleen tekst, zonder gast-TTS/STT.
- AI-tokengebruik voor gastvragen en verzoeknummers is expliciet toegestaan.
- Tekstvragen en verzoeknummers kunnen nog steeds AI-verwerking gebruiken;
  tekst-only betekent niet automatisch nul tokens of nul kosten.
- Voor een latere spraakversie zijn sessietoestemming, bronkeuze, verwerking
  per gast en limieten nodig. Kosten hangen af van de gekozen verwerking
  en het hergebruik van audio; nu geen bedragen of tokenbesparing claimen.

### Uitwerking en controle

- Dit vraagt een gezamenlijke Core-/Apple-uitwerking. Leg eerst de publieke
  gastprojectie, join-route, bevoegdheden, tijdelijke gesprekscontext en
  emotie-events vast in de canonieke Core-specificatie en afstemming.
- Controleer uitnodigingsrotatie, verlopen/toegangsintrekking, geïnstalleerde
  app versus installatie, joinbevestiging, leave/disconnect en dataverwijdering.
- Controleer isolatie tussen twee gasten, afwezigheid van hostprivédata,
  geblokkeerde playback-/instellingenacties, lege schermen en geen wijzigingen
  aan Music DNA/Ontdekt. Controleer daarnaast verzoeken, muziekinformatie,
  Horizon, Vibescape-dynamiek en live tv-emoties bij een nummerwisseling.
- Status: productscope geregistreerd; open keuzes hierboven expliciet benoemd.
  Contractontwerp, implementatie en runtime-/apparaatcontrole staan open.

## 24. VibeCast: teller voor verbonden gasten

- Verzoek: toon rechtsboven bij de statusicoontjes hoeveel gasten verbonden
  zijn met de actieve VibeCast-sessie.
- Gebruik het door Core bevestigde aantal actuele deelnemers; tel geen
  verlopen uitnodigingen, tv-schermen of beëindigde deelnames mee.
- Controleer join, leave, leaseverloop en hostintrekking, zonder privégegevens
  van gasten in de publieke statusweergave op te nemen.
- Status: geregistreerd; Core-contract, renderer en controles staan open.

## 25. Gastmodus: contextuele Ask DJ-help

- Toon in Ask DJ-help precies de vragen en acties die in de joined
  gastensessie beschikbaar zijn: gastverzoeken en toegestane muziekvragen.
- Geen hostbediening, wijzigingen aan sessiekenmerken of niet-ondersteunde
  acties aanbieden. Help en daadwerkelijke Core-bevoegdheden moeten overeenkomen.
- Controleer de help bij join en leave naast de bestaande eigenaarweergave.
- Status: geregistreerd; contractafstemming, implementatie en controles staan open.

## 26. Gastmodus: emoticons ook via de Ask DJ-chat

- Een gast kan ook een emoticon typen en verzenden via Ask DJ. Dit levert
  dezelfde muziekreactie op het huidige nummer als de vijf-iconenwerkbalk
  uit punt 23 en verschijnt in de live tv-emotielaag.
- Geen reactie op een bijdrage en geen Music DNA-feedback.
- Losse ondersteunde emoticoninvoer kan direct via de canonieke Core-
  emotieroute worden verwerkt, zonder AI-aanroep. Dit geeft geen lokale
  interpretatiebevoegdheid voor vrije tekst of playbackverzoeken.
- Controleer beide invoerroutes en de nummeridentiteit bij een nummerwisseling.
- Status: geregistreerd; contractafstemming, implementatie en controles staan open.

## 27. Gastmodus: terugkoppeling wanneer jouw verzoeknummer speelt

- Geef op de iPhone terugkoppeling wanneer de DJ het eigen verzoeknummer
  daadwerkelijk afspeelt, op basis van Core's bestaande `actually_playing`
  status voor het oorspronkelijke gastverzoek.
- Ontvangen, geaccepteerd of aan de wachtrij toegevoegd is nog geen bewijs
  van afspelen. Toon deze melding niet voor een verzoek van een andere gast.
- Toon de terugkoppeling in de actieve app één keer per bevestigd verzoek;
  na leave/disconnect volgen geen oude gastmeldingen meer.
- Achtergrondpush is alleen mogelijk via een bestaande expliciet toegestane
  notificatieroute; deze registratie claimt geen nieuwe APNs-functionaliteit.
- Controleer twee gasten, statusherhaling, nummerwisseling en leave.
- Status: geregistreerd; implementatie en controles staan open.

## 28. VibeCast Live: naam en tijdelijke gegevens

- De gastfunctie heet **VibeCast Live**.
- Bewaar de gedeelde Live-sessiegegevens nergens na afronding. Gastgesprekken,
  tijdelijke verzoekbindingen, emotie-events en snapshots blijven tijdelijk
  en worden bij leave, disconnect, intrekking of einde opgeruimd.
- Geen Live-geschiedenis herstellen. Dit is geen opdracht om de afzonderlijke
  persoonlijke geschiedenis van een gewone hostsessie te verwijderen.
- Publieke bijdragen zijn anoniem. Core bewaart alleen tijdelijk intern welk
  gastverzoek bij welke gast hoort voor persoonlijke terugkoppeling.
- Status: geregistreerd; implementatie en isolatie-/opruimcontroles in uitvoering.

## 29. VibeCast starten: Live aan of uit

- De host kiest bij het starten van VibeCast met een schakelaar of
  **VibeCast Live** actief is. Bestaand toestemmingsprincipe: standaard uit.
- Live aan maakt de gastfunctie en gast-QR beschikbaar; Live uit geeft geen
  gast-QR en laat geen nieuwe gastdeelname toe.
- De inhoudelijke tv-sessieflow is bij Live aan en uit gelijk. De schakelaar
  start geen andere DJ-sessie en selecteert geen andere DJ-content.
- Gebruik voor gastverzoeken het bestaande hostbeoordelingsbeleid; inschakelen
  betekent geen automatische playbackbevoegdheid voor gasten.
- Status: geregistreerd; Core-contract en Apple-consumer in uitvoering.

## 30. Host-afstandsbediening: Live wisselen en VibeCast stoppen

- De host kan in de VibeCast-afstandsbediening Live aan en uit zetten.
- Uitschakelen trekt gasttoegang en gast-QR in; reeds verbonden gasten worden
  beëindigd en hun tijdelijke gegevens opgeruimd.
- De host kan daar de volledige gedeelde VibeCast-sessie beëindigen. Dit
  betekent de VibeCast-share stoppen, niet stilzwijgend de muziek of de
  afzonderlijke DJ-sessie beëindigen.
- De stopknop van een gast blijft uitsluitend **Leave joined session**.
- Status: geregistreerd; contract, bediening en eigenaar-/gasttests in uitvoering.

## 31. Tv-weergave omschakelen tussen Vibescape en sessieflow

- De keuzen uit punt 12 bedienen de weergave op de tv, niet uitsluitend
  de lokale iPhone-weergave.
- VibeCast rendert Vibescape op het tv-scherm via WebGL of een vergelijkbare
  geschikte renderer. Geen extra microfoon- of audiobediening hiermee activeren.
- Status: geregistreerd; Core-renderer en hostbedieningscontract in uitvoering.

## 32. Vibescape volgt de sessie-instellingen

- Kleuren, vormen en dynamiek van de tv-Vibescape volgen de instellingen
  van de hostsessie; de tv kiest die niet onafhankelijk op basis van
  apparaatvoorkeuren.
- De gebruiker heeft bevestigd dat gasten alleen de dynamiek van hun eigen
  lokale Vibescape in de Apple-gastweergave mogen aanpassen. Dat wijzigt
  de tv of de sessie-instellingen van de host niet.
- Status: geregistreerd; contract en consumenten in uitvoering.

## 33. Ask DJ Moments: zoeken faalt vaak

- Gebruikersmelding met twee screenshots: tijdens **Children — Armin van
  Buuren**, album **Piano**, meldt de avatarcard **Het zoeken lukt nu even
  niet. Probeer het later nog eens.** met **Opnieuw controleren**, terwijl een
  Music Origin-kaart voor dat nummer wel zichtbaar is.
- Onderzoek de actuele gevraagde Moment-typen, de Core-resultaten en de
  fout-/herhaalweergave. Een bestaande kaart bewijst niet dat ieder ander
  Moment-type beschikbaar is.
- Verbeter de generieke route en fout-/herhaalafhandeling waar een oorzaak
  is aangetoond; geen uitzondering voor dit specifieke nummer of deze artiest.
- Controleer gedeeltelijk beschikbare typen, een verlopen of gewisseld nummer,
  een antwoord dat later binnenkomt en gelijktijdig opnieuw controleren.
- Status: geregistreerd met screenshots; Core en Apple onderzoeken parallel.

## Apple-uitvoering — tussenstand

- Apple-bron voor de witte startknoprand en ademende huidige track-art is
  toegevoegd, inclusief Minder beweging en achtergrond-/zichtbaarheidsgrenzen.
- Nieuwe shares vragen expliciet vier uur, app-taal en de Live-keuze aan;
  de deelsheet toont de werkelijke resterende tijd. Oude twee-uursrequests
  blijven compatibel; het bestaande maximum van acht uur is niet verlaagd.
- Een afzonderlijke native Live-gastclient en gastweergave zijn toegevoegd:
  gesloten uitnodigingsparser, expliciete deelname, aparte HTTPS-guesttransport,
  alleen RAM, publieke flow/Horizon, eigen gesprek en verzoeken, lege persoonlijke
  tabbladen, beperkte Help, lokale Vibescape en trackgebonden emoties.
- De eigen verzoekstatus geeft alleen bij `actually_playing` persoonlijke
  terugkoppeling; leave of intrekking verwijdert alle lokale gastgegevens.
- Het beëindigen van de hele VibeCast-share gebruikt de bestaande hostroute
  met verse eigenaarcontrole en onafhankelijke readback, zonder DJ-sessie-einde.
- Dit zijn bronwijzigingen, geen oplever- of installatieclaims. Gast-artwork
  vereist nog een afzonderlijk Core-gastdoel; geen eigenaar-/displaytoken hergebruiken.
- Eerste unsigned macOS-build eindigde met exit 0. De negen bestaande lokale
  checkfasejobs slagen. Vijf geïsoleerde gastclient-/parserchecks slagen op hun
  eigen vastgelegde bronkopie; de uitgebreidere bron vereist opnieuw tests.
- Volledige Swift-tests, iOS-build, echte simulatorbediening en onder meer
  host-remotecontrol, nieuwe Up-next-producer en Cast-SDK-aansluiting staan open.

## 34. Voor jou: keuzes verdwijnen na ongeveer vijftien seconden

- Gebruikersmelding: na circa vijftien seconden verdwijnt de inhoud van
  **Voor jou** en verschijnt de melding dat de keuzes niet beschikbaar of
  verlopen zijn. De kaart zelf blijft staan.
- Gemeld bij **Children — Armin van Buuren**, album **Piano**. Root heeft
  dezelfde melding ook in de werkelijk geïnstalleerde Mac-app waargenomen.
- Onderzoek apart de korte projectie-/contextlease en de oorspronkelijke
  geldigheid van het aanbod en zijn acties. De Apple-weergave gebruikt voor
  hetzelfde aanbod momenteel steeds de kortste eerder ontvangen deadline.
- Een verse bevoegde contextread moet een nog geldig aanbod bruikbaar kunnen
  houden zonder nieuwe modelaanroep. Dat rechtvaardigt geen onbeperkte lokale
  verlenging van oude keuzen of het verwijderen van vervalcontroles.
- Controleer op tijdstippen 14, 16 en 40 seconden, plus echte wijzigingen van
  onderwerp, eigenaar, sessie, bron of instellingen en verlopen acties.
- Status: Core heeft het zichtbare beslisbudget gescheiden van de voorbereiding. Apple bewaart de oorspronkelijke deadline en definitieve intrekking. Echte Core-wire-regressies op 14/16/40/60 seconden slagen; live iOS-herkwalificatie blijft open.

## 35. iOS Horizon: hapert en wordt na enkele seconden onbeschikbaar

- Gebruikersmelding met screenshot: de iOS-Horizonweergave hapert en toont
  na enkele seconden **Horizon is nu niet beschikbaar / Ververs pagina**.
  Rechtsboven zijn een oranje herstel-/verversingsicoon en spinner zichtbaar.
- Onderzoek de Horizon-readlease, vernieuwing en netwerk-/sessieherstelroute,
  ook naast punt 34. Een gezamenlijke oorzaak is nog niet bewezen.
- Houd nog geldige inhoud zichtbaar tijdens een gewone verversing; ingetrokken,
  verlopen of niet meer bij de sessie horende inhoud blijft onbeschikbaar.
- Controleer herhaalde verversingen, korte verbindingsonderbreking, echte
  vervaltijd en wisseling van sessie of eigenaar.
- Status: geregistreerd met screenshot; Core en Apple onderzoeken parallel.


36. **Help build432** — Suggesties blijft laden / uitgebreide Help kan muziekmogelijkheden niet bevestigen. Contextread en herstel onderzoeken, geen capabilities verzinnen. Open runtimeonderzoek.
37. **iPad/Mac bijdrage-layout** — Alle DJ-bijdragen met trackthumbnail plaatsen tekst rechts naast art, top-aligned; iPhone compact behouden. Gedeelde kolomlayout geïmplementeerd, geometry/runtimecontrole volgt. Originele foto/Canvas-hero blijft onderscheiden.
38. **Nauwkeurigheidszin** — Generieke “Je DJ kan zich vergissen” uit de gedeelde sessie/Ask DJ composer verwijderd en in volledige Help geplaatst, vijf bestaande vertalingen. Inhoudelijke onzekerheid/bronnen blijven.
39. **Track Insight tijdtekst** — Numerieke voortgangstijd uit animatie verwijderd; animatie en reguliere playbacktijd elders behouden.
40. **Track Insight continuïteit** — Equalizer moet hele nummer vloeiend blijven; gemarkeerde golf/balk volgt echte playbackprogress. Onderzoek observatielease versus immutable analyse, test15/30/60s en volledige korte track, pause/resume/seek/trackwissel/end clamp. Geen verzonnen audioanalyse of leaseverlenging.
41. **Apple equalizer navigatie** — Tap/klik op playbackequalizer opent Track Insight voor huidige nummer, toegankelijk als knop. Alleen Apple; geen VibeCast-TVwijziging. Toegankelijke equalizerknop en expliciete TrackInsight-sluitactie geïmplementeerd; iOS UI-test gecompileerd, interactieve deviceacceptatie nog open.
42. **Live Activity push** — Expliciet geautoriseerd iPhone-kanaal activeren, echte update en afmelden verifiëren. Geen afgeleid consent voor Widgets/Moments/Watch. Onderzoek bestaande ActivityKit enrollment/tokenrotatie/withdrawal; fysieke signing/providerkwalificatie apart.

43. **Grote widget push** — Expliciete opdracht Widgets-kanaal naast Live Activities; laatste geldige DJ-bijdrage uit actuele sessie/profile, owner/source-fences en wissen bij afmelding/sessie-einde/profilewissel. Geen willekeurige cached Moment/private Ask DJ; echte WidgetKit wakebudgetten en fysieke pushreadback verifiëren.

44. **Alle widgetformaten blijven actueel** — Push/backgroundflow na appsluiting moet nieuwe geautoriseerde updates blijven ontvangen, ook na vorige TTL; werkelijke afmelding/sessie-einde wist content. Geen onbeperkte cache of private-grant-bypass; WidgetKit scheduling werkelijk kwalificeren. Bestaande pushhandler aanwezig, originele credential/publicatieketen nog onderzoeken.

45. **Watch Moments push** — Expliciet Moments-alertkanaal: voorgrondmelding, één tap opent exact originele Momentkaart, sluiten terug Watchhoofdscherm. Bestaande djc-watch-moment/1 parser/taprouter/by-ID renderer behouden; voorgrondbanner nu beperkt tot expliciete kanaalkeuze en actuele sessiebinding. Geen afgeleide Smart Stack-toestemming. Watchbuild en echte APNs/deviceacceptatie volgen.

46. **Watch Smart Stack push** — Afzonderlijk expliciet geselecteerd kanaal watch_smart_stack. Canonieke Watch-widgettarget DJConnectComplication/dev.djconnect.ios.watch.complications, eigen WidgetPushHandler en lokale tokencustody; geen iPhone-clock/grant of Moments-alertconsent. Originele Watch enrollment/issuer/read/clockport moet nog werkelijk kwalificeren; geen activatieclaim op basis van bron alleen.


Vervolgvalidatie: macOS build-for-testing geslaagd; echte native run met14tests geslaagd, inclusief Horizon19fencegevallen en bijdragegeometry3breedtes×4typen. De latere gast-art/Watch-pushbronwijzigingen vallen nog buiten deze build. Negen bestaande contract-/lokalisatie-/hygienechecks opnieuw geslaagd. Simulatorbaseline cfa55 demo TrackInsight toont na circa16s gewijzigde balken/deeltjes en voortgaande playhead; dit reproduceert live lease-probleem niet. GUI/XCUITestbediening ontbreekt op deze host; officiële CLI screenshots zijn echte rendererframes, geen interactieve UIacceptatie. Nieuwe iOS equalizer-navigatietest toegevoegd maar nog niet uitgevoerd.


Aanvullende kwalificatie: Watchsimulatorbuild op07b4c28 geslaagd. Mac art-build en16gerichte tests geslaagd. Bredere surface-pushcontrole draaide65tests:64geslaagd, één oude unsupported-platformverwachting accepteerde nog geen inmiddels canoniek geselecteerde Watchplatform; aangepast naar echt unsupported visionos, met aanvullende causale test dat een Watchreceipt GEEN oorspronkelijke iPhonecandidate autoriseert. Nieuwe monotonicartdeadline/pause/observed-playbacktests waren al geslaagd in die run. Laatste vervolgbron houdt pausepresentatie gescheiden van analyserights, gebruikt monotonic playbackinterpolatie, bewaart originale artdeadline en toont observed_playback als metadatatype met gekwalificeerde Spotifyattributie. Nieuwe bron vereist nog build/testafronding.


Laatste Macvervolg: build-for-testing geslaagd;68native regressies in5suites geslaagd (mac-qualified-test.log/xcresult), inclusief originele monotonic artdeadline, volledige trackprogress/pause/seek/clockcorrecties, guest observed metadata-only/leave, WatchcanonicalHTTPtarget en causale Watchreceipt→iPhoneweigering. Bronkwalificatie is geen fysieke push-/installatieacceptatie. Host32 heeft aanvullend canoniek dynamics-ackcontract ontvangen; aparte consumeradoptie volgt.


Punt3 vervolgbron: canonieke owner-only horizon_moment geadopteerd; nullable snapshot/events, actual queue/current-session/item/playing/last45s/expiry-fences, originele lokale deadlinepins alleen op accepted-owner-ingress (geen renderrenewal), tijdelijke kaart met echte Coreintro/titel/artist/owner-imageproxy/Spotifylogo. Geen TTS, history, selectedMoment of Watchalert.20 echte Coreproducerfixturecases (synthetic source/queue/fakeclock expliciet, originele expiry behouden) met SHA f6514e4c6ed24c3b5bf434f18918ad4081e88644bb4dfe846657abe61815dc77 toegevoegd; decoder/fencetests en echte native renderer40breedte/taal/personacaptures voorbereid. Bron parseert, build/test volgt na extra opslagruimte.
Punt32 vervolgbron: echte owner view.dynamics ack, expliciete bounded dynamics met onafhankelijke readback, huidige hostvisit session/epoch-fence, slider alleen op edit-einde verzenden en eigen remote-TVslider; gastdynamiek blijft device-local. Positieve wirebody en negatieve mismatch-readbacktest voorbereid; nog geen runtime/deploymentclaim.

47. **Expliciet album wordt genegeerd** — Echte oude HA-devruntime322: “Speel Children van Armin van Buuren van het album Piano op Denon Home 150 Schuur” resulteert in album What If I Told You. Core/receiver onderzoeken generieke parse/albumconstraint; geen Apple-transcript of metadata blind aanpassen. Dit is geen bewezen modeltrace. Apple blijft originele tekst/context doorgeven.

Actuele status35: smalle Horizontransportfix is gecommit in df1cdd1: alleen getypeerde tijdelijke netwerkfouten behouden een nog geldige oorspronkelijke cursor binnen ongewijzigde owner/session/source/epoch. Geen leaseverlenging;19 causale fencegevallen geslaagd in de68-test Macrun. Echte iOS-runtimekwalificatie blijft open. Status34 blijft onderzoek: native VoorYou gebruikt de oorspronkelijke Core expires_in met minimum-deadlinepins voor hetzelfde offer; geen lokale15slease vastgesteld.

Checkpoint3/32/36: definitieve Mac build-for-testing geslaagd en116testfuncties in7suites geslaagd (help-preview-assets-test.log/xcresult). Inclusief7echte AppModel-ingressfences met originele Corepreviewbytes,90sHelp met echte nieuwe GETresponses en replay/hide/context/authfences, hostdynamiek wirebody en onafhankelijke mismatchreadback.40native previewcapturen met echte shippingSpotifyasset; NL768 en DE320 visueel gecontroleerd: intro/titel/artist/logo leesbaar, wrapping zonder afkapping. StandaloneXCTestasset wordt uitsluitend in testhost geladen. Negen lichte contract-/lokalisatie-/hygienechecks opnieuw geslaagd. Dit checkpoint bevat geen nieuwe fysieke installatie, APNsacceptatie of iOS-runtimeacceptatie.


Checkpoint 24 november — Voor jou, Widgets en Cast:
- Bevroren macOS build-for-testing geslaagd; geen bronwijzigingen tijdens compilatie.
  139 testfuncties in zeven suites geslaagd (`widget-sdk-final-test.log/xcresult`).
- Voor jou gebruikt ongewijzigde echte Coreproducer-fixtures met expliciet
  synthetische bron/fakeclock. Geldige keuzes blijven op 14/16/40 seconden;
  oorspronkelijke expiry, source-withdrawal en instellingen-intrekking blijven
  definitief. Oude beschikbare DTOs kunnen geen ingetrokken aanbod heropenen.
- Gewone Widget-keuze gebruikt nu de oorspronkelijke serverrevisie en operatie,
  onafhankelijke readback en het geselecteerde productaudience. Afmelden blijft
  behouden bij direct opnieuw aanmelden en herstart. AppAttest-fasen worden vóór
  hun effect vastgelegd; onbekende uitkomsten starten geen vervangende sleutel.
  Consent, sleutel-ACK en native read-/clockbevoegdheid blijven aparte feiten.
- De Widget-prepareclient transporteert uitsluitend de gesloten originele ACK;
  runtime-mount en gekwalificeerde native clock blijven afzonderlijk open.
- Echte Google Cast SDK-adapter en elf contractregressies geïntegreerd. De
  officiële iOS-dependency is exact vastgezet. Appmodel-/schermintegratie,
  volledige iOS-link, consolekwalificatie en fysieke Cast-acceptatie staan open.
- iOS-checkpoint 532132d bouwde en draaide werkelijk via officiële simulator-CLI;
  video en frames op 30 en 70 seconden tonen doorlopende demo-animatie/progress.
  Dat bewijst geen live provider-incident of interactieve navigatie. De host mist
  Simulator-GUI; de volgende volledige runtimeproef gebruikt een nieuwe eigen
  DeviceSet. Alleen onze oude inactieve simulator is verwijderd; alle bewijs,
  producten en testresultaten zijn behouden.
- Fysieke pushactivering/afmelding, Live Activity en afzonderlijke Watchkanalen
  zijn nog niet end-to-end gekwalificeerd. Er is geen nieuwe installatieclaim.


Aanvullend checkpoint 24 november:
- Echte iOS simulator-build en Google Cast-frameworklink op 958f390 geslaagd.
  Watch-app plus Smart Stack-extensie op 9824642 bouwen eveneens succesvol.
- Gast-artwork: werkelijke grant-intrekking wist onmiddellijk de eigen joined
  scope; een gewone afbeeldingsfout doet dit niet. Causale regressie geslaagd.
- Track Insight behandelt opaque provider-ID's nu casegevoelig, zodat een ander
  nummer met vergelijkbare metadata zijn eigen progress-anchor krijgt.
  Mac-build en 141 regressies in zeven suites geslaagd, inclusief gehele
  trackduur, pause/resume/seek en de nieuwe casegevoelige trackwissel.
- Onafhankelijke bronreview van exact 958f390: GO zonder P1/P2 voor oorspronkelijke
  SDK-fasen, ON/OFF/ON-consentqueue en definitieve Voor-jou-intrekking.
  De reviewer heeft de tests niet onafhankelijk herhaald.
- Echte reauthorization met bestaande AppAttest-sleutel, originele role-ACK en
  native clock-/signed-environmentproducer blijven afzonderlijke integratiegates.
  Een oud journal of statusantwoord vervangt die bevoegdheden niet.


Cast/production-ACK checkpoint 24 november:
- iOS-compositie initialiseert de echte Google Cast SDK één keer, met SDK-
  payloadlogging uit. De iPhone-schermkiezer toont echte SDK-device-ID's en
  verbindt via de bestaande eigenaarroute `POST /session/broadcast/token`.
  Eén expliciete connect gebruikt één oorspronkelijke tokenread/handoff.
- Achtergrond en geschiedenis-suspend stoppen lokale observatie zonder TV-stop.
  De oude statuslease herleeft niet; opnieuw verbinden vraagt expliciete intent
  en verse ownercontext. Echte pairing/origin/token/Profile/Session-intrekking,
  Demo-overgang en Stop trekken uitsluitend de oorspronkelijke owned view in.
- Verloren lokale SDK/statusobservatie detacht zonder TV-stop. Eigen gestarte
  SDK-sessies en hergebruikte sessies houden hun afzonderlijke exacte custody;
  onopgeloste startcallbacks kunnen een onmiddellijke herconnect tijdelijk
  blokkeren. Geen friendly-name/Bonjour- of DefaultMediaReceiverfallback.
- Mac-build en 143 regressies in zeven suites geslaagd. Tien causale Cast-
  AppModelcases gebruiken echte HTTP-ingress met expliciet synthetische
  HTTPS-/ownerresponses en gemodelleerde SDK; geen fysieke CAF-acceptatie.
- De production first-key-ACK vereist exact de twee extra Apple-evidence/status-
  expiraties als safe-int DATA; oorspronkelijke challenge-expiry blijft gelijk.
  De oorspronkelijke 120s-challenge wordt daarmee niet verlengd.
- Eén gerichte herstart van uitsluitend de eigen simulatorgebruikersdiensten
  herstelde officiële inventarisatie. Nieuwe eigen DeviceSet/device aangemaakt;
  geen globale runtime-/daemon-/Devices-permissiewijziging. Nieuwe runtime-QA
  volgt op de iOS-build. Live/4h/QR blijft onafhankelijk van de legacy Cast-token.
