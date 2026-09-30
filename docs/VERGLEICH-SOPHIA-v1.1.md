# Kienzlefon AI und IONOS / Sophia – Qualitätsvergleich

[Zur README](../README.md) · Stand: 30. September 2026

Die vom Projektbetreiber nachgereichte inhaltliche Auswertung ergänzt die technischen Testdaten. **In diesen historischen Tests hatte Kienzlefon Vorteile bei palliativen Notfällen und dringlichen Fachanrufern; Sophia trennte neue AU und gleichzeitig bestelltes Rezept teilweise besser.** Beide Systeme zeigten konkrete Schwächen. Eine gemeinsame Gesamtnote oder vergleichende Stimmbenotung wurde nicht vergeben.

Verglichen werden **Kienzlefon Backend 1.9.6 („Archive 4“), vier Durchläufe derselben 150 synthetischen Szenarien vom 21.08.2026**, und **Sophia, ein Durchlauf mit 150 Szenarien vom 14.09.2026**. Die 600 Kienzlefon-Ausführungen sind Wiederholungen, keine 600 verschiedenen Szenarien. Sophia-Produkt- und Modellversion sind nicht ausgewiesen.

## Fachliche Ergebnisse auf einen Blick

Die Zahlen geben die Befunde der nachgereichten Auswertung wieder; mit „ca.“ markierte Sophia-Werte sind dort nur näherungsweise angegeben. Bei Kienzlefon ist die vorgesehene Aktion im Dialogkern erfasst, bei Sophia wird die beobachtete Notfall-/Weiterleitungsreaktion bewertet.

| Bereich | Kienzlefon „Archive 4“ | IONOS / Sophia |
|---|---|---|
| Klassische Notfallszenarien KF-051–070 | **80/80 (100 %)** erkannt | **ca. 20/20 (ca. 100 %)** mit Notfall-/Weiterleitungsreaktion |
| Palliative Notfallszenarien KF-071–080 | **37/40 (92,5 %)** erkannt | **ca. 5/10 (ca. 50 %)** mit eindeutiger Reaktion |
| Dringliche Fachanrufer KF-028–031 und KF-050 | **20/20 (100 %)** als dringend eingeordnet | **4/5 (80 %)** mit Durchstellung; Arztkollege KF-050 blieb in Rückfragen |
| Formulare KF-096–100: richtiger Auftragstyp | **16/20 (80 %)** | **4/5 (80 %)**; in den Sonstiges-JSONs fehlten strukturierte Personenfelder |
| Neue AU und Rezept im selben Gespräch | Problematisch; Schleife in einem Durchlauf | Rezept als eigener Auftrag erhalten; AU-Regel wich weiterhin vom gewünschten Praxisablauf ab |
| Notfalldokumentation vor Weiterleitung | Im Kienzlefon-Konzept vorgesehen | Nach Sophia-Regel kein JSON bei Weiterleitung; dies allein ist kein Speicherfehler |

Sophia war bei einfachen Rezepten und Überweisungen brauchbar: Ein passender Auftragstyp entstand in **13/16 Rezeptfällen** und **9/10 Überweisungsfällen**. Dennoch gingen im Mehrmedikamentenfall KF-002 ein Medikament und in KF-014 eine genannte Stärke verloren. Ein passender Typ bedeutet daher noch keinen vollständigen Auftrag.

Weitere inhaltliche Befunde der übergebenen Auswertung: Bei akuten Pflege-/Pflegedienstfällen KF-124–130 und KF-133 zeigten nur **2/8** eine eindeutige Notfallreaktion. Verwechslungen zwischen anrufender und betroffener Person traten auf. Terminwünsche wurden häufig durchgestellt; ein Termin-JSON entstand im vollständigen Sophia-Lauf nicht. Bei einigen Fällen ohne Weiterleitung wurden stattdessen Rückruf-, Sonstiges- oder Fallback-Datensätze erzeugt. Diese Befunde beschreiben die damalige Testkonfiguration, keine allgemeine Aussage über heutige Anbieterstände.

## Sophia: Speicherung unter Berücksichtigung von Weiterleitungen

Von 49 separat vorliegenden Ergebnis-JSONs gehören **47 zum vollständigen Lauf**; zwei stammen aus früheren Anläufen. Die 47 Datensätze verteilen sich auf **43 Szenarien**, vier davon mit jeweils zwei Datensätzen. Diese zeitliche Zuordnung wurde bei der Dokumentationsaktualisierung bestätigt.

Die inhaltliche Auswertung betrachtet 84 Szenarien, die grundsätzlich einen Datensatz erwarten. Davon waren 30 technisch fehlgeschlagen. Bei den übrigen 54 fehlte zwölfmal ein JSON; neun dieser Fälle waren tatsächlich weitergeleitet worden. Nach der für Sophia vorgegebenen Regel ist dort kein JSON zu erwarten.

| Bereinigtes Ergebnis laut Auswertung | Sophia |
|---|---:|
| Technisch erfolgreiche, nicht durch Weiterleitung von der Speicherung ausgenommene Fälle | **45** |
| Davon mit Datensatz | **42/45 (93,3 %)** |
| Auftragstypen stimmen exakt mit Testsoll überein | **30/45 (66,7 %)** |
| Fehlender Datensatz trotz Speicherpflicht | **3/45 (6,7 %)**: KF-023, KF-046, KF-049 |

Die 93,3 % gelten nur für diese bereinigte Teilmenge. Sie sind keine Gesamt-Erfolgsquote über alle 150 Szenarien. Regelkonforme Weiterleitungen ohne JSON werden nicht als Datenverlust gezählt. Die Auswertung bemängelte außerdem Export-/Rufnummernformate; deren Ursache kann auch in der Telefonieintegration liegen.

## Technischer Ablauf und Gesprächsfluss

| Kennzahl | Kienzlefon „Archive 4“ | Sophia |
|---|---:|---:|
| Technisch bestanden | **586/600 (97,7 %)** | **83/150 (55,3 %)** |
| Technisch fehlgeschlagen | **14/600 (2,3 %)** | **67/150 (44,7 %)** |
| Gesprächslimit erreicht | **14/600 (2,3 %)** | **6/150 (4,0 %)** |
| Sprachtransportfehler | Im Texttest nicht geprüft | **61/150 (40,7 %)** |

**Die technischen Quoten sind kein Vergleich unter gleichen Bedingungen:** Kienzlefon lief über die Textschnittstelle mit Telefon-Dialogregeln, ohne ASR/TTS/SIP; Sophia über den echten Telefon-/Audiopfad. Kienzlefon-Anfragen zur Weiterleitung wurden im Texttransport protokolliert, nicht als reale Telefonweiterleitung ausgeführt. Testsuite und Gesprächslimits unterscheiden sich ebenfalls. Ein technischer PASS ist keine fachliche Qualitätsnote.

Laut nachgereichter Auswertung waren zehn der 61 Sophia-Sprachtransportfehler mit einer erkennbaren Weiterleitung verbunden; der geschlossene Medienpfad kann dort deren Folge sein. Bei den übrigen 51 war keine Weiterleitung erkennbar. Das belegt Probleme im getesteten Ablauf, lokalisiert ihre Ursache aber nicht abschließend. Die Auswertung zählt zudem **241 Rückfragen, ob noch jemand in der Leitung sei, in 100/150 Szenarien**. In **147/150** war nach ausbleibender verwertbarer Begrüßung innerhalb von fünf Sekunden eine initiale Anrede durch die Testsuite nötig. Telefonieroute, Testsimulator und Zielsystem sind bei der Interpretation gemeinsam zu berücksichtigen.

## Konsequenzen für Kienzlefon

- Die Trennung mehrerer Anliegen und insbesondere der Erhalt eines Rezeptauftrags neben einer AU-Anfrage sind sinnvolle Regressionstests. Die damalige AU-Schleife bleibt ein dokumentierter Schwachpunkt von „Archive 4“.
- Notfallerkennung, dringliche Fachanrufer und die Trennung von Anrufer und Patient verdienen eigene Prüfkategorien. Gute Typquoten ersetzen keine Prüfung aller Auftragsdetails.
- Eine angenehmere Stimme bleibt ein eigener nächster Entwicklungsschritt. Aus diesem Dialogvergleich folgt keine Aussage über die Natürlichkeit der aktuellen Qwen-Stimme.

## Quellen und Prüfstand

Die fachlichen Bewertungen stammen aus dem am **30.09.2026 vom Projektbetreiber übergebenen früheren Analysebericht** (`Pasted text.txt`). Die Dokumentation fasst diesen Bericht zusammen; sie ist keine neue vollständige Bewertung aller Gespräche. Der Bericht wurde nicht ungefiltert in die öffentliche Dateiauswahl kopiert, da er unter anderem konkrete Rufnummern enthält.

Lokal zusätzlich geprüft wurden die vier Manifeste und die strukturierten Ergebnisse in `runs/Archive 4.zip`, das Sophia-Manifest `20260914_133457Z_sophia_all_D41D890D`, seine Einzelvalidierungen und die Zeitstempel der separaten Ergebnisexporte. Bestätigt sind die technischen Summen, die Archive-4-Zähler 80/80 und 37/40 für die Aktion `rotes_telefon`, 20/20 dringliche Fachanrufer mit vorgesehener Weiterleitung, 16/20 Formularfälle mit Typ `sonstiges` sowie die Sophia-Zuordnung 47 JSONs zu 43 Szenarien. Die detaillierten Sophia-Inhaltsurteile und die bereinigte Speicherquote wurden aus dem nachgereichten Bericht übernommen; sie wurden hier nicht erneut vollständig semantisch bewertet.

`semantic_evaluation: NOT_PERFORMED` bleibt in den ursprünglichen Manifesten korrekt: Die Testsuite selbst führte keine semantische Bewertung durch. Die nachgereichte, getrennte Inhaltsanalyse ergänzt diesen automatischen Status. Die [erste Übersicht 1.0](VERGLEICH-SOPHIA-v1.0.md) entstand vor ihrer Übergabe und verwendete außerdem einen anderen Kienzlefon-Referenzlauf (Backend 1.9.9, 147/150). Dessen 98,0 % werden nicht mit den 97,7 % von „Archive 4“ vermischt.

SHA-256 des übergebenen Analyseberichts:

```text
b9b9f3cb494a0c99a4aa11ad2404d8862ebd5a173c58e7faa4b6ef8ebdc18386
```

Die Ergebnisse gelten für die damaligen synthetischen Tests, nicht als Abnahme der aktuellen Runtime 2.5.x oder als klinische Validierung. Es wurden keine neuen Anrufe, Hardwaretests oder vergleichenden Hörtests durchgeführt. Rohtranskripte, Audiodateien und private Verbindungsdaten bleiben außerhalb dieser öffentlichen Übersicht.
