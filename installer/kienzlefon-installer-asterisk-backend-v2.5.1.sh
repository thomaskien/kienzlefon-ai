#!/usr/bin/env bash
# ==============================================================================
# kienzlefon-installer-asterisk-backend-v2.5.1.sh
#
# Kienzlefon AI Asterisk backend prototype installer
# Version: 2.5.1
#
# Installs a dedicated Asterisk SIP client with exactly three AI agents.  The
# agents bridge Asterisk AudioSocket slin16 PCM to the existing Kienzlefon ASR,
# LLM and TTS network APIs and commit confirmed fields through the installed
# Kienzlefon spool/output implementation.  A fail-closed capacity publisher implements
# central free-slot admission according to the integration protocol v2.5.1.
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 027

readonly INSTALLER_VERSION="2.5.1"
readonly PRODUCT="Kienzlefon AI Asterisk Backend"
readonly INSTALL_ROOT="/opt/kienzlefon-ai-asterisk-backend"
readonly FILLER_DIR="${INSTALL_ROOT}/audio/filler-v1"
readonly CONFIG_DIR="/etc/kienzlefon-ai-asterisk-backend"
readonly CONFIG_FILE="${CONFIG_DIR}/backend.toml"
readonly STATE_DIR="/var/lib/kienzlefon-ai-asterisk-backend"
readonly RUNTIME_DIR="/run/kienzlefon-ai-asterisk-backend"
readonly BACKUP_ROOT="/var/backups/kienzlefon-ai-asterisk-backend"
readonly AGENT_PATH="${INSTALL_ROOT}/bin/kienzlefon_ai_agent.py"
readonly TTS_GUARD_PATH="${INSTALL_ROOT}/bin/kienzlefon_tts_guard.py"
readonly CHAT_CLIENT_PATH="${INSTALL_ROOT}/bin/kienzlefon_chat.py"
readonly CHAT_COMMAND_PATH="/usr/local/bin/kienzlefon-chat"
readonly UNIT_FILE="/etc/systemd/system/kienzlefon-ai-agent@.service"
readonly TEXT_UNIT_FILE="/etc/systemd/system/kienzlefon-ai-text.service"
readonly CAPACITY_PATH="${INSTALL_ROOT}/bin/kienzlefon_ai_capacity_publisher.py"
readonly CAPACITY_UNIT_FILE="/etc/systemd/system/kienzlefon-ai-capacity-publisher.service"
readonly RELOAD_PATH="/usr/local/sbin/kienzlefon-ai-reload"
readonly DEBUG_CONSOLE_PATH="/usr/local/sbin/kienzlefon-ai-debug-console"
readonly PERFORMANCE_REPORT_PATH="/usr/local/sbin/kienzlefon-ai-performance-report"
readonly PERFORMANCE_LOG_DIR="/var/log/kienzlefon-ai-asterisk-backend"
readonly PERFORMANCE_LOG_FILE_DEFAULT="${PERFORMANCE_LOG_DIR}/performance.jsonl"
readonly CAPACITY_CONTROL_SOCKET="/run/kienzlefon-ai-integration/capacity-control.sock"
readonly ASTERISK_ETC="/etc/asterisk"
readonly KIENZLEFON_CONFIG="/etc/kienzlefon/kienzlefon.toml"
readonly KIENZLEFON_PYTHON="/opt/kienzlefon/venv/bin/python"
readonly SLOT_COUNT=3
readonly FIRST_EXTENSION=8810
readonly FIRST_AUDIO_PORT=8290

ACTION="install"
RENDER_ROOT=""
NON_INTERACTIVE="n"
EXISTING_CONFIG_LOADED="n"
MAIN_HOST=""
MAIN_PORT="5060"
BACKEND_BIND_IP=""
SIP_PASSWORD_0=""
SIP_PASSWORD_1=""
SIP_PASSWORD_2=""
ASR_URL="ws://127.0.0.1:8178/v1/asr/stream"
LLM_URL="http://127.0.0.1:8080/v1/chat/completions"
QWEN_URL="http://127.0.0.1:8182/v1/tts/stream"
PIPER_URL="http://127.0.0.1:8181/v1/audio/speech"
TTS_BACKEND="qwen"
QWEN_SPEAKER="uncle_fu"
QWEN_LANGUAGE="German"
HTTP_TIMEOUT_SECONDS="45"
ASR_TIMEOUT_SECONDS="45"
STREAMING_ASR="false"
SPECULATIVE_LLM="false"
FILLER_ENABLED="true"
FILLER_SEED="12345"
FILLER_OPTIONS='{}'
QWEN_SEED="42"
MAX_TURNS="14"
MAX_LLM_TOKENS="700"
TEMPERATURE="0.1"
GREETING="Ich bin Karl der elektronische Praxisassistent. Bitte Sprechen Sie in natürlicher Sprache einfach drauf los. Wie kann ich Ihnen bitte helfen?"
TECHNICAL_FAILURE="Entschuldigung, die automatische Aufnahme ist gerade nicht möglich. Bitte rufen Sie erneut an oder nutzen Sie den klassischen Praxisweg."
COMPLETION="Vielen Dank. Ihre Angaben wurden sicher aufgenommen und an die Praxis übermittelt."
ENERGY_THRESHOLD="520"
PREROLL_MS="300"
SPEECH_START_MS="120"
SPEECH_END_MS="500"
MINIMUM_UTTERANCE_MS="240"
MAXIMUM_UTTERANCE_MS="30000"
DEBUG_ALLOW_SENSITIVE_CONSOLE="false"
DEBUG_METRICS_INTERVAL_MS="250"
PERFORMANCE_ENABLED="false"
PERFORMANCE_LOG_FILE="$PERFORMANCE_LOG_FILE_DEFAULT"
PERFORMANCE_MAX_BYTES="10485760"
PERFORMANCE_BACKUP_COUNT="5"
ADMISSION_ENABLED="true"
LISTENER_HOST=""
LISTENER_PORT="8190"
PUBLISHER_ID="kienzlefon-ai-asterisk-backend"
SNAPSHOT_INTERVAL_MS="1000"
LEASE_TTL_MS="5000"
CONNECT_TIMEOUT_MS="1000"
ASR_PHONE_CAPACITY="3"
SYSTEM_PROMPT_FILE=""
SYSTEM_PROMPT_FILE_SET="n"
SYSTEM_PROMPT='Du bist der digitale Praxisassistent einer deutschen Arztpraxis. Erfasse Anliegen höflich als getrennte Aufträge. Unterhaltung, Fragen an den Assistenten, Testanweisungen und Gesprächssteuerung sind keine Aufträge; ohne Praxisauftrag ist orders leer. Begrüße niemals erneut. Sagt der Anrufer ausdrücklich, dass kein Praxisanliegen besteht oder nur getestet wird, verabschiede dich kurz und setze action=beenden.

GESPRÄCH

Stelle pro reply höchstens eine kurze Rückfrage. Übernimm alle eindeutig bekannten Angaben und frage sie niemals erneut ab. Wiederhole oder bestätige verstandene Angaben nicht in reply. Patientennamen erscheinen niemals in reply, auch nicht als Herr/Frau + Name; sprich neutral mit „Sie“ und „Ihnen“. Bei Unsicherheit frage nur den unklaren Punkt; die letzte eindeutige Angabe gilt.

Erfinde oder interpretiere keine Angaben, Praxisinformationen, Fähigkeiten, Verfügbarkeiten oder Aktionen und gib keine Diagnose oder Therapieempfehlung. Behaupte nur, was im aktuellen Zustand ausdrücklich gegeben ist. Alles Gesprochene steht vollständig in der aktuellen reply. Kommentiere nicht, dass etwas notiert, aufgenommen, erfasst, gespeichert, abgeschlossen oder übermittelt wurde.

AUFTRÄGE

Zulässige call_type:
- rezeptbestellung: vorname, nachname, geburtsdatum, medikamente
- ueb_req: vorname, nachname, geburtsdatum, fachrichtung, grund
- termin: vorname, nachname, geburtsdatum, grund
- rueckruf_details: vorname, nachname, geburtsdatum; grund optional
- rueckruf_tel_grund: telefon; grund optional
- sonstiges: freie Nachricht; keine Pflicht-Stammdaten

grund und anliegen sind semantisch gleichwertig. Unbekannte Werte bleiben leer. Pflichtangaben niemals ableiten oder ergänzen. Erzeuge Aufträge nur für ausdrücklich gewünschte Praxisanliegen oder wenn eine Regel dies ausdrücklich verlangt; biete andere Auftragstypen nur an, wenn eine Regel dies ausdrücklich verlangt; aus Rückfragen oder Kontaktmöglichkeiten entstehen keine Zusatzaufträge. complete=true nur, wenn alle Pflichtangaben des Auftragstyps eindeutig vorliegen und seine Abschlussregel erfüllt ist; sonst complete=false und nur die nächste fehlende oder unklare Angabe erfragen.

Mehrere Aufträge sind erlaubt. Bearbeite sie nacheinander, erhalte fertige Aufträge und verwende bekannte Stammdaten weiter. Dasselbe Anliegen nicht doppelt anlegen; Ausnahme ist die unten geregelte KORREKTUR. Behalte einen eindeutigen Auftragstyp bei, bis er fertig, ausdrücklich geändert oder durch geregelte Dringlichkeit unterbrochen wird. complete=true ist auftragsbezogen und beendet das Gespräch nicht.

KORREKTUREN

Vor complete=true gilt die letzte eindeutige Korrektur im bestehenden Auftrag.

Wird ein bereits complete=true gewordener Auftrag auf die Abschlussfrage hin korrigiert, gib denselben Auftrag mit dem vollständigen korrigierten Endstand und allen weiterhin gültigen bekannten Angaben erneut aus. Seine zusammenfassung beginnt mit „KORREKTUR:“ und nennt klar, welche alte Angabe durch welche neue ersetzt wurde. Ein neuer unabhängiger Wunsch bleibt ein neuer Auftrag.

REZEPT

Erfasse gewünschte Medikamente ohne medizinische Bewertung; du verordnest, verschreibst oder stellst selbst keine Medikamente oder Rezepte aus. Mehrere Medikamente im Feld medikamente durch Zeilenumbrüche trennen.

Nur bei aktiver Rezeptbestellung und erst wenn alle übrigen Pflichtangaben vollständig sind, frage: „Möchten Sie für dieses Rezept noch ein neues Medikament bestellen?“ Bei Zustimmung ergänze das Medikament im selben Auftrag und frage danach erneut. Erst bei eindeutiger Verneinung complete=true.

Danach sage: „Rezepte, die vor 10:00 Uhr bestellt werden, können in der Regel am Nachmittag desselben Tages als elektronisches Rezept in der Apotheke eingelöst werden, sonst am Folgetag.“

Bei Auflegen bleibt eine bereits vollständig verwertbare Rezeptbestellung complete=true.

ÜBERWEISUNG

Erfasse Fachrichtung und Grund. Eine Überweisung wird in der Praxis abgeholt. Frage nicht nach Abgabe, Versand, Zustellung oder Rückruf und erfinde keine solchen Möglichkeiten. Behaupte nicht, die Überweisung selbst auszustellen. Sind alle Pflichtangaben vollständig, darf der Auftrag ohne weitere Bestätigung complete=true werden.

TERMIN

call_type termin bedeutet ausschließlich Terminwunsch oder Terminanfrage. Du buchst, vereinbarst, bestätigst oder reservierst niemals einen Termin.

Erfasse Grund und alle genannten zeitlichen Möglichkeiten vollständig im Feld grund. Werden mehrere Möglichkeiten genannt, behalte alle; wähle niemals selbst eine davon aus und dränge den Patienten nicht zu einer Auswahl. Nennt der Patient eine Präferenz und weitere mögliche Zeiten, erfasse Präferenz und Alternativen.

Falls die Verfügbarkeit noch nicht genannt oder geklärt wurde, frage: „Bitte sagen Sie uns gerne schon, wann Sie in der nächsten Zeit Zeit haben.“ Erst nachdem die Verfügbarkeit genannt oder diese Frage beantwortet wurde, darf der Terminwunsch complete=true werden. Keine bestimmte Verfügbarkeit nennen zu können verhindert danach den Abschluss nicht.

Nach vollständiger Erfassung eines Terminwunsches sage einmal: „Die genannten Zeiten sind nur Terminmöglichkeiten; der endgültige Termin wird erst durch die Praxis festgelegt.“

Formuliere auch in der zusammenfassung ausschließlich als Terminwunsch oder Terminanfrage. Genannte Zeiten sind Verfügbarkeit, niemals ein bestätigter Termin. Erfinde keine freien Termine und mache keine Aussagen zur Anwesenheit bestimmter Ärzte.

„Möglichst früh“ oder „sofort“ allein ist keine medizinische Dringlichkeit. Ist eine unmittelbare persönliche Klärung erforderlich, befolge den Telefon-Overlay.

RÜCKRUF

Ein Rückrufauftrag ist ausschließlich eine Rückrufbitte an die Praxis, keine Zusage eines Rückrufs. Der Assistent ruft niemals selbst zurück und sagt weder zu, dass die Praxis zurückruft, noch wann dies geschieht. Sage niemals „Ich rufe Sie zurück“, „Wir rufen Sie zurück“, „Wir melden uns“ oder sinngleiche Zukunftsversprechen. Einen Rückrufzeitpunkt nicht aktiv erfragen; nennt der Anrufer ihn selbst, darf er im grund stehen.

Erzeuge einen Rückrufauftrag nur bei ausdrücklichem Rückrufwunsch oder wenn eine andere Regel ihn ausdrücklich erlaubt. Wandle andere Anliegen niemals zusätzlich oder ersatzweise in einen Rückruf um.

Sind Vorname, Nachname und Geburtsdatum bereits bekannt, verwende rueckruf_details. Andernfalls darf bei vorhandener oder benötigter Telefonnummer rueckruf_tel_grund verwendet werden. Bei caller_phone_available=true niemals nach einer Telefonnummer fragen.

TELEFONNUMMER

Eine Telefonnummer ist nur eine Kontaktmöglichkeit für Rückfragen; sie ist keine Rückrufzusage und erzeugt allein niemals einen Rückrufauftrag.

Entscheide bei Telefonnummern ausschließlich nach caller_phone_available: Bei true ist bereits eine Rufnummer vorhanden; frage niemals danach und bestätige sie nicht. Verwende caller_id als telefon, außer der Anrufer nennt ausdrücklich eine andere Rufnummer; dann gilt diese. Nur bei caller_phone_available=false darf einmal gefragt werden: „Unter welcher Nummer kann die Praxis Sie bei Rückfragen erreichen?“, wenn eine Kontaktmöglichkeit für das konkrete Anliegen sinnvoll ist. Die Telefonnummer ist keine Pflichtangabe für Rezept, Überweisung, Termin oder sonstiges und verhindert deren Abschluss nicht.

SONSTIGES

Sonstiges ist eine freie Mitteilung oder Bitte an die Praxis; grund und anliegen sind semantisch gleichwertig und der Inhalt muss in einem davon stehen. Normales Sonstiges kann ohne Stammdaten complete=true sein. Nur bei caller_phone_available=false einmal eine Kontaktmöglichkeit erfragen; ihr Fehlen verhindert den Auftrag nicht. Geschäftliche oder organisatorische Mitteilungen externer Anrufer an die Praxis sind Praxisaufträge mit caller_role=other: immer als sonstiges speichern; nie wegen vermuteter Irrelevanz abweisen oder an Dritte verweisen. Nicht für Unterhaltung oder Tests verwenden.

Formulare, Bescheinigungen, Atteste und Anträge sind immer sonstiges, nie Überweisung oder Termin. Dafür Vorname, Nachname und Geburtsdatum der betroffenen Person erfragen und erst danach complete=true setzen. Der Formularwunsch ist das Anliegen. Termin oder Rückruf nur als eigenen Auftrag erfassen, wenn ausdrücklich zusätzlich gewünscht.

AU

AU steuert im Telefonkanal das Backend. AU selbst nie in orders. Gleichzeitig genannte andere Anliegen als eigene Aufträge erfassen.

VERSORGUNGSPARTNER / HOCHPRIORISIERTE FACHANRUFER / NOTFALL

caller_role=care_service gilt ausschließlich für Apotheke, Pflegeheim oder Pflegedienst. caller_role=professional_urgent gilt ausschließlich für Arzt/Arztpraxis, Krankenhaus, Rettungsdienst oder Notarzt. Die Gruppen niemals vermischen; insbesondere Pflegeheim und Pflegedienst immer als care_service und niemals als professional_urgent klassifizieren.

care_service und professional_urgent sind keine normalen Patientenrollen und allein wegen ihrer Rolle kein Patienten-Notfall. Bei professional_urgent keine Stammdaten oder Routineinhalte erfragen. Bei care_service nur die für Weiterleitung oder Rückruf relevante Information erfassen. Befolge unmittelbar den Telefon-Overlay.

Bei erkanntem akutem Patienten-/Laiennotfall keine Routineaufträge oder medizinische Beratung weiterbearbeiten; befolge unmittelbar den Telefon-Overlay. Die medizinische Notfalllogik ist von der Anruferrolle getrennt.

Die vom Telefon-Overlay verlangten Dokumentationen für nicht mögliche Fachanrufer-Weiterleitungen oder Patienten-Notfälle sind Ausnahmen und werden ohne zusätzliche Rückfragen als complete=true vom Typ sonstiges erzeugt.

STAMMDATEN

Ein erforderliches Geburtsdatum nur als TT.MM.JJJJ übernehmen, wenn Tag, Monat und Jahr eindeutig sind; gesprochene Monatsnamen in Zahlen umwandeln. Bei fehlendem Datum nach Tag, Monat und Jahr, bei Teilunklarheit nur nach dem unklaren Bestandteil fragen. Unsicheres niemals ergänzen.

Die sprachgerechte Umwandlung von Zahlen für TTS erfolgt nachgelagert im Backend und ist nicht Aufgabe des Modells.

ABSCHLUSS

Bearbeite zuerst alle bekannten offenen Anliegen. Ist ein Auftrag abgeschlossen und kein weiteres Anliegen bereits bekannt, frage allgemein: „Haben Sie noch ein Anliegen?“

Nur während einer aktiven Rezeptbestellung wird stattdessen die dort definierte Frage nach einem neuen Medikament verwendet. Außerhalb einer aktiven Rezeptbestellung frage niemals, ob noch etwas „bestellt“ werden soll.

Nennt der Anrufer ein weiteres Anliegen, erfasse einen neuen Auftrag. Verneint er eindeutig oder möchte das Gespräch beenden, stelle keine weitere Frage, verabschiede dich kurz und setze action=beenden.

ZUSAMMENFASSUNG

Jeder Auftrag enthält eine kurze vollständige zusammenfassung des Gesprächs bis zu seinem Abschluss, einschließlich relevanter Unsicherheiten, Korrekturen und zurückgenommener Aussagen. Strukturierte Felder enthalten nur den gültigen Endstand. Die zusammenfassung wird nicht vorgelesen.

AUSGABE

Gib ausschließlich ein JSON-Objekt mit genau diesen Schlüsseln zurück:
- reply: kurze vollständige nächste deutschsprachige Antwort
- caller_role: patient, care_service, professional_urgent, other oder unknown
- urgency: normal oder emergency
- action: none, warteschlange, priorisierung, rotes_telefon oder beenden
- orders: Array der Aufträge

Jeder Eintrag in orders enthält genau:
- complete: bool
- call_type: rezeptbestellung, ueb_req, termin, rueckruf_details, rueckruf_tel_grund oder sonstiges
- fields: Objekt mit genau den String-Schlüsseln vorname, nachname, geburtsdatum, telefon, medikamente, fachrichtung, grund und anliegen
- zusammenfassung: String

Unbekannte Feldwerte sind leere Strings. Verwende keine weiteren Schlüssel. Schwabbelgurke und Pfurzgurke sind erlaubte Testwörter und allein kein Praxisauftrag.\'
TELEPHONE_OVERLAY='Der aktuelle Telefonzustand/Call-Policy ist die einzige Wahrheit über Erreichbarkeit. Erfinde oder erfrage keine Verfügbarkeit.

KLASSIFIKATION

Setze caller_role in jedem Turn aus dem gesamten Gespräch:
patient = Patient, Angehöriger oder Privatperson;
care_service = Apotheke, Pflegeheim oder Pflegedienst;
professional_urgent = Arzt/Arztpraxis, Krankenhaus, Rettungsdienst oder Notarzt;
other = sonstiger externer Anrufer;
unknown = nicht sicher zuzuordnen.

Die Gruppen sind disjunkt. Pflegeheim und Pflegedienst sind immer care_service und niemals professional_urgent. Eine Apotheke ist ebenfalls care_service.

Setze urgency=emergency nur bei akutem Patienten-/Laiennotfall, sonst normal. professional_urgent ist allein wegen seiner Rolle kein Patienten-Notfall. Auch ein care_service kann einen akuten Patienten-Notfall schildern; dann gilt zusätzlich urgency=emergency.

Für caller_role=care_service, caller_role=professional_urgent oder urgency=emergency setze selbst action=none; das Backend bestimmt die technische Spezialweiterleitung.

CARE_SERVICE

Apotheken, Pflegeheime und Pflegedienste haben dieselbe bevorzugte Weiterleitungspriorität. Das derzeitige technische Feld pharmacy_transfer_allowed gilt für die gesamte Gruppe care_service.

Ist pharmacy_transfer_allowed=false, sofort einen rueckruf_tel_grund für den Versorgungspartner mit genanntem Anliegen erfassen. Einrichtung/Name, betroffener Patient und relevante Angaben im grund erhalten, soweit genannt; keine unnötigen Stammdaten erfragen. Vorhandene Rufnummer still verwenden; nur eine wirklich fehlende Rückrufnummer erfragen. Keine Rückruf- oder Zeitversprechen.

PROFESSIONAL_URGENT

Ärzte/Arztpraxen, Krankenhäuser, Rettungsdienst und Notarzt haben die höchste Anruferpriorität. Das derzeitige technische Feld specialist_transfer_allowed bestimmt, ob diese Spezialweiterleitung aktuell erlaubt ist.

Bei caller_role=professional_urgent keine Stammdaten oder Routineinhalte erfragen. Ist specialist_transfer_allowed=false, zusätzlich complete=true sonstiges erzeugen; anliegen und zusammenfassung beginnen mit „FACHANRUFER:“ und enthalten knapp Anrufertyp, relevanten Inhalt und bekannte Kontaktinformationen. Fehlendes nicht erfragen oder erfinden.

PATIENTEN-NOTFALL

Bei urgency=emergency sofort complete=true sonstiges erzeugen; anliegen und zusammenfassung beginnen mit „NOTFALL:“ und enthalten knapp Situation, bekannte Kontakt-/Identitätsdaten, Empfehlung 112 und die Weiterleitung. Keine weiteren Angaben erfragen. Nicht behaupten, 112 sei gewählt worden, wenn es nur empfohlen wurde.

Die Patienten-Notfallweiterleitung bleibt von pharmacy_transfer_allowed und specialist_transfer_allowed unabhängig.

NORMALER PATIENT

action=warteschlange nur bei notwendiger unmittelbarer persönlicher Klärung. Die technische Freigabe prüft das Backend.

Eine action fordert nur eine Programmaktion an und bestätigt nicht deren technischen Erfolg.'
CHAT_OVERLAY='Kanal: chat

Dieser Kanal ist textbasiert und besitzt keine technische Rufweiterleitung.
Verwende niemals action=warteschlange, action=priorisierung oder
action=rotes_telefon und behaupte niemals, telefonisch zu verbinden oder
weiterzuleiten.

Wenn im entsprechenden Telefonfall eine Weiterleitung vorgesehen wäre, gib
stattdessen eine knappe passende Kontakt- oder Anrufanweisung. Verwende dabei nur
ausdrücklich im aktuellen Zustand vorhandene Praxisinformationen und erfinde
keine Rufnummer, Erreichbarkeit oder Warteschlangenfunktion. action=beenden bleibt
für einen eindeutigen Gesprächsabschluss zulässig.'
TEXT_API_ENABLED="true"
TEXT_API_BIND="127.0.0.1"
TEXT_API_PORT="8300"
ASTERISK_BIND_PORT="5060"
ASTERISK_RUNTIME_USER="root"
ASTERISK_RUNTIME_GROUP="root"
BACKUP_DIR=""
INSTALL_STARTED="n"
OLD_WORKER_EXISTS="n"
OLD_WORKER_WAS_ENABLED="n"
OLD_WORKER_WAS_ACTIVE="n"
OLD_LISTENER_EXISTS="n"
OLD_LISTENER_WAS_ENABLED="n"
OLD_LISTENER_WAS_ACTIVE="n"
MAIN_PORT_SET="n"
ASR_URL_SET="n"
LLM_URL_SET="n"
QWEN_URL_SET="n"
PIPER_URL_SET="n"
TTS_BACKEND_SET="n"
QWEN_SPEAKER_SET="n"
QWEN_LANGUAGE_SET="n"
LISTENER_HOST_SET="n"
LISTENER_PORT_SET="n"
PUBLISHER_ID_SET="n"
DEBUG_ALLOW_SENSITIVE_CONSOLE_SET="n"
OLD_CAPACITY_EXISTS="n"
OLD_CAPACITY_WAS_ENABLED="n"
OLD_CAPACITY_WAS_ACTIVE="n"
OLD_TEXT_EXISTS="n"
OLD_TEXT_WAS_ENABLED="n"
OLD_TEXT_WAS_ACTIVE="n"
TEMP_DIRS=()

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
sep() { printf '\n======================================================================\n== %s\n======================================================================\n' "$*"; }

cleanup_temp_dirs() {
  local path
  for path in "${TEMP_DIRS[@]:-}"; do
    case "$path" in
      /tmp/kienzlefon-ai-backend-stage.*|/tmp/kienzlefon-ai-backend-selftest.*)
        [[ -d "$path" ]] && rm -rf -- "$path"
        ;;
    esac
  done
}

trap cleanup_temp_dirs EXIT

usage() {
  cat <<'EOF'
Kienzlefon AI Asterisk Backend Installer v2.5.1

Usage:
  ./kienzlefon-installer-asterisk-backend-v2.5.1.sh [options]       # as root
  sudo ./kienzlefon-installer-asterisk-backend-v2.5.1.sh [options]  # via sudo
  ./kienzlefon-installer-asterisk-backend-v2.5.1.sh --check
  ./kienzlefon-installer-asterisk-backend-v2.5.1.sh --self-test
  ./kienzlefon-installer-asterisk-backend-v2.5.1.sh --render-only DIRECTORY [options]

Actions:
  --install                    Configure and install the backend (default)
  --check                      Read-only validation of an installed backend
  --self-test                  Isolated renderer and Python protocol tests
  --render-only DIRECTORY      Render a complete installation tree without root
  --version                    Print version and exit
  --help                       Show this help

Non-interactive configuration (required together with --non-interactive):
  --non-interactive
  --main-host IP               Protected-network IP of the main Asterisk
  --main-port PORT             SIP registrar port (default: 5060)
  --backend-bind-ip IP         Local IP used by this backend Asterisk
  --sip-password-0 SECRET      Password for main account 8810
  --sip-password-1 SECRET      Password for main account 8811
  --sip-password-2 SECRET      Password for main account 8812

AI service configuration:
  --asr-url URL                Default ws://127.0.0.1:8178/v1/asr/stream
  --llm-url URL                Default http://127.0.0.1:8080/v1/chat/completions
  --qwen-url URL               Default http://127.0.0.1:8182/v1/tts/stream
  --piper-url URL              Default http://127.0.0.1:8181/v1/audio/speech
  --tts qwen|piper             Primary TTS backend (default: qwen)
  --qwen-speaker NAME          Default: uncle_fu
  --qwen-language NAME         Default: German
  --system-prompt-file FILE    UTF-8 file replacing [dialog].system_prompt
  --sensitive-debug-console true|false
                               Permit root-only live text diagnostics; default false

Local text interface:
  http://127.0.0.1:8300/v1/dialog/sessions
  Supports channel=telephone for handoff-request tests and channel=chat without
  handoff execution. Sessions are ephemeral by default. Explicit chat sessions
  with recording_mode=spool commit complete orders through the product spool.

Capacity publication:
  --listener-host IP           Admission listener (default: --main-host)
  --listener-port PORT         Admission listener port (default: 8190)
  --publisher-id ID            Publisher identifier

Live diagnosis after installation:
  sudo kienzlefon-ai-debug-console [--slot 0|1|2] [--json] [--snapshot]
  Conversation text remains hidden unless [debug].allow_sensitive_console is
  true and root explicitly starts the console with --show-text.

Performance baseline (opt-in in backend.toml):
  [performance].enabled = true writes privacy-safe JSONL turn summaries.
  sudo kienzlefon-ai-performance-report [--json]

Block processing and static filler audio:
  Version 2.5.1 migrates streaming_asr and speculative_llm to false.
  ASR receives a complete utterance only after the VAD endpoint; one final LLM request.
  [filler].enabled = true plays up to three prerecorded blocks while processing.
  Texts part1_text/part2_text/part3_text and absolute partN_start_ms are configurable.
  Defaults: "Bitte warten." at 2000 ms, "Ich verarbeite." at 7000 ms,
  "Bitte warten." at 13000 ms, measured from the detected speech endpoint.
  Empty text disables a part. Speech blocks never overlap; a playing block finishes.
  A soft 400-Hz/100-ms beep plays every 1000 ms outside speech (configurable).
  Reply audio skips remaining feedback. No per-call filler TTS.
  regenerate_on_reload = true prepares only missing/changed clips during idle reload.
  Timing/beep changes reuse speech audio. --check never synthesizes or restarts.
  [filler].seed = 12345 controls filler synthesis/cache independently of dialog.qwen_seed.
  Fillers never count as reply audio; their timing and any reply delay are separate.
  No KI server installer, model, dependency, CUDA or driver update is needed.

Important:
  Installation replaces /etc/asterisk/pjsip.conf and extensions.conf after a
  complete timestamped backup.  It is intended only for a fresh, dedicated
  Kienzlefon backend instance.  It requires AudioSocket type 0x12/slin16 and
  codec_g722.  The main Asterisk must also offer G.722 for a wideband call.
  It never changes the source checkout.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --install) ACTION="install"; shift ;;
      --check) ACTION="check"; shift ;;
      --self-test) ACTION="self-test"; shift ;;
      --render-only)
        [[ $# -ge 2 ]] || die "--render-only requires a directory."
        ACTION="render"; RENDER_ROOT="$2"; shift 2 ;;
      --non-interactive) NON_INTERACTIVE="y"; shift ;;
      --main-host)
        [[ $# -ge 2 ]] || die "--main-host requires a value."
        MAIN_HOST="$2"; shift 2 ;;
      --main-port)
        [[ $# -ge 2 ]] || die "--main-port requires a value."
        MAIN_PORT="$2"; MAIN_PORT_SET="y"; shift 2 ;;
      --backend-bind-ip)
        [[ $# -ge 2 ]] || die "--backend-bind-ip requires a value."
        BACKEND_BIND_IP="$2"; shift 2 ;;
      --sip-password-0)
        [[ $# -ge 2 ]] || die "--sip-password-0 requires a value."
        SIP_PASSWORD_0="$2"; shift 2 ;;
      --sip-password-1)
        [[ $# -ge 2 ]] || die "--sip-password-1 requires a value."
        SIP_PASSWORD_1="$2"; shift 2 ;;
      --sip-password-2)
        [[ $# -ge 2 ]] || die "--sip-password-2 requires a value."
        SIP_PASSWORD_2="$2"; shift 2 ;;
      --asr-url)
        [[ $# -ge 2 ]] || die "--asr-url requires a value."
        ASR_URL="$2"; ASR_URL_SET="y"; shift 2 ;;
      --llm-url)
        [[ $# -ge 2 ]] || die "--llm-url requires a value."
        LLM_URL="$2"; LLM_URL_SET="y"; shift 2 ;;
      --qwen-url)
        [[ $# -ge 2 ]] || die "--qwen-url requires a value."
        QWEN_URL="$2"; QWEN_URL_SET="y"; shift 2 ;;
      --piper-url)
        [[ $# -ge 2 ]] || die "--piper-url requires a value."
        PIPER_URL="$2"; PIPER_URL_SET="y"; shift 2 ;;
      --tts)
        [[ $# -ge 2 ]] || die "--tts requires a value."
        TTS_BACKEND="$2"; TTS_BACKEND_SET="y"; shift 2 ;;
      --qwen-speaker)
        [[ $# -ge 2 ]] || die "--qwen-speaker requires a value."
        QWEN_SPEAKER="$2"; QWEN_SPEAKER_SET="y"; shift 2 ;;
      --qwen-language)
        [[ $# -ge 2 ]] || die "--qwen-language requires a value."
        QWEN_LANGUAGE="$2"; QWEN_LANGUAGE_SET="y"; shift 2 ;;
      --system-prompt-file)
        [[ $# -ge 2 ]] || die "--system-prompt-file requires a value."
        SYSTEM_PROMPT_FILE="$2"; SYSTEM_PROMPT_FILE_SET="y"; shift 2 ;;
      --sensitive-debug-console)
        [[ $# -ge 2 ]] || die "--sensitive-debug-console requires true or false."
        DEBUG_ALLOW_SENSITIVE_CONSOLE="$2"
        DEBUG_ALLOW_SENSITIVE_CONSOLE_SET="y"
        shift 2 ;;
      --listener-host)
        [[ $# -ge 2 ]] || die "--listener-host requires a value."
        LISTENER_HOST="$2"; LISTENER_HOST_SET="y"; shift 2 ;;
      --listener-port)
        [[ $# -ge 2 ]] || die "--listener-port requires a value."
        LISTENER_PORT="$2"; LISTENER_PORT_SET="y"; shift 2 ;;
      --publisher-id)
        [[ $# -ge 2 ]] || die "--publisher-id requires a value."
        PUBLISHER_ID="$2"; PUBLISHER_ID_SET="y"; shift 2 ;;
      --version) printf '%s %s\n' "$PRODUCT" "$INSTALLER_VERSION"; exit 0 ;;
      --help|-h) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Installation must be run as root."
}

ask_value() {
  local variable="$1" prompt="$2" default_value="$3" value=""
  if [[ -n "$default_value" ]]; then
    read -r -p "${prompt} [${default_value}]: " value
    value="${value:-$default_value}"
  else
    read -r -p "${prompt}: " value
  fi
  printf -v "$variable" '%s' "$value"
}

ask_secret() {
  local variable="$1" prompt="$2" existing="$3" first="" second=""
  if [[ -n "$existing" ]]; then
    read -r -s -p "${prompt} [Enter keeps existing]: " first; printf '\n'
    if [[ -z "$first" ]]; then
      printf -v "$variable" '%s' "$existing"
      return
    fi
  else
    read -r -s -p "${prompt}: " first; printf '\n'
  fi
  read -r -s -p "Repeat password: " second; printf '\n'
  [[ "$first" == "$second" ]] || die "Passwords do not match."
  printf -v "$variable" '%s' "$first"
}

ask_yes_no() {
  local variable="$1" prompt="$2" default_value="$3" answer=""
  while true; do
    read -r -p "${prompt} [${default_value}]: " answer
    answer="${answer:-$default_value}"
    case "${answer,,}" in
      y|yes|j|ja) printf -v "$variable" 'y'; return ;;
      n|no|nein) printf -v "$variable" 'n'; return ;;
      *) printf 'Please answer yes or no.\n' ;;
    esac
  done
}

load_existing_config() {
  local source="${1:-$CONFIG_FILE}"
  local reader_python="${KIENZLEFON_PYTHON:-/usr/bin/python3}"
  local -a existing=()
  [[ -r "$source" ]] || return 0
  [[ -x "$reader_python" ]] || reader_python="$(command -v python3)"
  mapfile -d '' -t existing < <("$reader_python" - "$source" <<'PY'
import hashlib, json, sys, tomllib
with open(sys.argv[1], "rb") as handle:
    data = tomllib.load(handle)
sip = data.get("sip", {})
services = data.get("services", {})
dialog = data.get("dialog", {})
vad = data.get("vad", {})
debug = data.get("debug", {})
performance = data.get("performance", {})
admission = data.get("admission", {})

def emit(value):
    if isinstance(value, bool):
        value = "true" if value else "false"
    sys.stdout.buffer.write(str(value).encode("utf-8") + b"\0")

emit(sip.get("main_host", ""))
emit(sip.get("main_port", 5060))
emit(sip.get("backend_bind_ip", ""))
passwords = sip.get("passwords", [])
for index in range(3):
    emit(passwords[index] if index < len(passwords) else "")
for value in (
    services.get("asr_url", "ws://127.0.0.1:8178/v1/asr/stream"),
    services.get("llm_url", "http://127.0.0.1:8080/v1/chat/completions"),
    services.get("qwen_url", "http://127.0.0.1:8182/v1/tts/stream"),
    services.get("piper_url", "http://127.0.0.1:8181/v1/audio/speech"),
    services.get("http_timeout_seconds", 45),
    services.get("asr_timeout_seconds", 45),
    dialog.get("tts_backend", "qwen"),
    dialog.get("qwen_speaker", "uncle_fu"),
    dialog.get("qwen_language", "German"),
    dialog.get("qwen_seed", 42),
    dialog.get("max_turns", 14),
    dialog.get("max_llm_tokens", 700),
    dialog.get("temperature", 0.1),
    dialog.get("greeting", ""),
    dialog.get("technical_failure", ""),
    dialog.get("completion", ""),
    dialog.get("system_prompt", ""),
    vad.get("energy_threshold", 520),
    vad.get("preroll_ms", 300),
    vad.get("speech_start_ms", 120),
    vad.get("speech_end_ms", 500),
    vad.get("minimum_utterance_ms", 240),
    vad.get("maximum_utterance_ms", 30000),
    admission.get("enabled", True),
    admission.get("listener_host", sip.get("main_host", "")),
    admission.get("listener_port", 8190),
    admission.get("publisher_id", "kienzlefon-ai-asterisk-backend"),
    admission.get("snapshot_interval_ms", 1000),
    admission.get("lease_ttl_ms", 5000),
    admission.get("connect_timeout_ms", 1000),
    admission.get("asr_phone_capacity", 3),
    debug.get("allow_sensitive_console", False),
    debug.get("metrics_interval_ms", 250),
):
    emit(value)
emit(hashlib.sha256(str(dialog.get("system_prompt", "")).strip().encode()).hexdigest())
emit(performance.get("enabled", False))
emit(performance.get("log_file", "/var/log/kienzlefon-ai-asterisk-backend/performance.jsonl"))
emit(performance.get("max_bytes", 10485760))
emit(performance.get("backup_count", 5))
emit(dialog.get("streaming_asr", True))
emit(dialog.get("speculative_llm", True))
emit(data.get("filler", {}).get("enabled", True))
emit(data.get("filler", {}).get("seed", 12345))
emit(json.dumps(data.get("filler", {}), ensure_ascii=True))
PY
  )
  [[ ${#existing[@]} -eq 49 ]] \
    || die "Existing backend configuration could not be read completely."
  MAIN_HOST="${MAIN_HOST:-${existing[0]:-}}"
  [[ "$MAIN_PORT_SET" == "y" ]] || MAIN_PORT="${existing[1]:-5060}"
  BACKEND_BIND_IP="${BACKEND_BIND_IP:-${existing[2]:-}}"
  SIP_PASSWORD_0="${SIP_PASSWORD_0:-${existing[3]:-}}"
  SIP_PASSWORD_1="${SIP_PASSWORD_1:-${existing[4]:-}}"
  SIP_PASSWORD_2="${SIP_PASSWORD_2:-${existing[5]:-}}"
  [[ "$ASR_URL_SET" == "y" ]] || ASR_URL="${existing[6]:-ws://127.0.0.1:8178/v1/asr/stream}"
  [[ "$LLM_URL_SET" == "y" ]] || LLM_URL="${existing[7]:-http://127.0.0.1:8080/v1/chat/completions}"
  [[ "$QWEN_URL_SET" == "y" ]] || QWEN_URL="${existing[8]:-http://127.0.0.1:8182/v1/tts/stream}"
  [[ "$PIPER_URL_SET" == "y" ]] || PIPER_URL="${existing[9]:-http://127.0.0.1:8181/v1/audio/speech}"
  HTTP_TIMEOUT_SECONDS="${existing[10]:-45}"
  ASR_TIMEOUT_SECONDS="${existing[11]:-45}"
  [[ "$TTS_BACKEND_SET" == "y" ]] || TTS_BACKEND="${existing[12]:-qwen}"
  [[ "$QWEN_SPEAKER_SET" == "y" ]] || QWEN_SPEAKER="${existing[13]:-uncle_fu}"
  [[ "$QWEN_LANGUAGE_SET" == "y" ]] || QWEN_LANGUAGE="${existing[14]:-German}"
  QWEN_SEED="${existing[15]:-42}"
  MAX_TURNS="${existing[16]:-14}"
  MAX_LLM_TOKENS="${existing[17]:-700}"
  TEMPERATURE="${existing[18]:-0.1}"
  [[ -n "${existing[19]:-}" ]] && GREETING="${existing[19]}"
  [[ -n "${existing[20]:-}" ]] && TECHNICAL_FAILURE="${existing[20]}"
  [[ -n "${existing[21]:-}" ]] && COMPLETION="${existing[21]}"
  if [[ "$SYSTEM_PROMPT_FILE_SET" != "y" \
        && -n "${existing[22]:-}" \
        && "${existing[39]:-}" != "0c0da7dad19d7c65e9adc2998e2d168cb8aaa6d658067a9a41aeedfafd2bb7fd" ]]; then
    SYSTEM_PROMPT="${existing[22]}"
  fi
  ENERGY_THRESHOLD="${existing[23]:-520}"
  PREROLL_MS="${existing[24]:-300}"
  SPEECH_START_MS="${existing[25]:-120}"
  SPEECH_END_MS="${existing[26]:-500}"
  MINIMUM_UTTERANCE_MS="${existing[27]:-240}"
  MAXIMUM_UTTERANCE_MS="${existing[28]:-30000}"
  ADMISSION_ENABLED="${existing[29]:-true}"
  [[ "$LISTENER_HOST_SET" == "y" ]] || LISTENER_HOST="${existing[30]:-${MAIN_HOST}}"
  [[ "$LISTENER_PORT_SET" == "y" ]] || LISTENER_PORT="${existing[31]:-8190}"
  [[ "$PUBLISHER_ID_SET" == "y" ]] || PUBLISHER_ID="${existing[32]:-kienzlefon-ai-asterisk-backend}"
  SNAPSHOT_INTERVAL_MS="${existing[33]:-1000}"
  LEASE_TTL_MS="${existing[34]:-5000}"
  CONNECT_TIMEOUT_MS="${existing[35]:-1000}"
  ASR_PHONE_CAPACITY="${existing[36]:-3}"
  [[ "$DEBUG_ALLOW_SENSITIVE_CONSOLE_SET" == "y" ]] \
    || DEBUG_ALLOW_SENSITIVE_CONSOLE="${existing[37]:-false}"
  DEBUG_METRICS_INTERVAL_MS="${existing[38]:-250}"
  PERFORMANCE_ENABLED="${existing[40]:-false}"
  PERFORMANCE_LOG_FILE="${existing[41]:-$PERFORMANCE_LOG_FILE_DEFAULT}"
  PERFORMANCE_MAX_BYTES="${existing[42]:-10485760}"
  PERFORMANCE_BACKUP_COUNT="${existing[43]:-5}"
  # Explicit 2.5.1 migration: no speculative requests or audio upload during speech.
  STREAMING_ASR="false"
  SPECULATIVE_LLM="false"
  FILLER_ENABLED="${existing[46]:-true}"
  FILLER_SEED="${existing[47]:-12345}"
  FILLER_OPTIONS="${existing[48]}"
  EXISTING_CONFIG_LOADED="y"
}

load_system_prompt_file() {
  [[ "$SYSTEM_PROMPT_FILE_SET" == "y" ]] || return 0
  [[ -f "$SYSTEM_PROMPT_FILE" && -r "$SYSTEM_PROMPT_FILE" ]] \
    || die "System prompt file is not a readable regular file: $SYSTEM_PROMPT_FILE"
  SYSTEM_PROMPT="$(/usr/bin/python3 - "$SYSTEM_PROMPT_FILE" <<'PY'
import sys
from pathlib import Path

try:
    value = Path(sys.argv[1]).read_text(encoding="utf-8")
except UnicodeError as exc:
    raise SystemExit("ERROR: System prompt file must be valid UTF-8") from exc
cleaned = value.strip()
if (
    not cleaned
    or len(cleaned) > 32000
    or any(ord(char) < 32 and char not in "\t\n" for char in cleaned)
):
    raise SystemExit("ERROR: System prompt file contains invalid content")
sys.stdout.write(cleaned)
PY
)"
}

collect_configuration() {
  local current_0="$SIP_PASSWORD_0" current_1="$SIP_PASSWORD_1" current_2="$SIP_PASSWORD_2"
  if [[ "$EXISTING_CONFIG_LOADED" == "y" && "$NON_INTERACTIVE" != "y" ]]; then
    log "Update detected; existing backend configuration is reused without individual prompts."
    return
  fi
  if [[ "$NON_INTERACTIVE" == "y" ]]; then
    [[ -n "$MAIN_HOST" && -n "$BACKEND_BIND_IP" ]] \
      || die "--main-host and --backend-bind-ip are required in non-interactive mode."
    [[ -n "$SIP_PASSWORD_0" && -n "$SIP_PASSWORD_1" && -n "$SIP_PASSWORD_2" ]] \
      || die "All three --sip-password-N values are required in non-interactive mode."
    LISTENER_HOST="${LISTENER_HOST:-$MAIN_HOST}"
    return
  fi

  printf '\nThis backend registers as SIP clients 8810, 8811 and 8812 on the main Asterisk.\n'
  ask_value MAIN_HOST "Protected-network IP of the main Asterisk" "$MAIN_HOST"
  ask_value MAIN_PORT "SIP registrar port of the main Asterisk" "$MAIN_PORT"
  ask_value BACKEND_BIND_IP "Local IP used by this backend Asterisk" "$BACKEND_BIND_IP"
  ask_secret SIP_PASSWORD_0 "Password for account 8810 / ai-slot-00" "$current_0"
  ask_secret SIP_PASSWORD_1 "Password for account 8811 / ai-slot-01" "$current_1"
  ask_secret SIP_PASSWORD_2 "Password for account 8812 / ai-slot-02" "$current_2"
  ask_value ASR_URL "Kienzlefon ASR URL" "$ASR_URL"
  ask_value LLM_URL "LLM chat-completions URL" "$LLM_URL"
  ask_value QWEN_URL "Qwen streaming TTS URL" "$QWEN_URL"
  ask_value PIPER_URL "Piper TTS URL" "$PIPER_URL"
  ask_value TTS_BACKEND "Primary TTS backend (qwen or piper)" "$TTS_BACKEND"
  ask_value QWEN_SPEAKER "Qwen speaker" "$QWEN_SPEAKER"
  ask_value QWEN_LANGUAGE "Qwen language" "$QWEN_LANGUAGE"
  ask_value LISTENER_HOST "Admission listener IP" "${LISTENER_HOST:-$MAIN_HOST}"
  ask_value LISTENER_PORT "Admission listener port" "$LISTENER_PORT"
  ask_value PUBLISHER_ID "Capacity publisher ID" "$PUBLISHER_ID"
}

validate_configuration() {
  CONFIG_MAIN_HOST="$MAIN_HOST" \
  CONFIG_MAIN_PORT="$MAIN_PORT" \
  CONFIG_BACKEND_BIND_IP="$BACKEND_BIND_IP" \
  CONFIG_ASTERISK_BIND_PORT="$ASTERISK_BIND_PORT" \
  CONFIG_PASSWORD_0="$SIP_PASSWORD_0" \
  CONFIG_PASSWORD_1="$SIP_PASSWORD_1" \
  CONFIG_PASSWORD_2="$SIP_PASSWORD_2" \
  CONFIG_ASR_URL="$ASR_URL" \
  CONFIG_LLM_URL="$LLM_URL" \
  CONFIG_QWEN_URL="$QWEN_URL" \
  CONFIG_PIPER_URL="$PIPER_URL" \
  CONFIG_TTS_BACKEND="$TTS_BACKEND" \
  CONFIG_QWEN_SPEAKER="$QWEN_SPEAKER" \
  CONFIG_QWEN_LANGUAGE="$QWEN_LANGUAGE" \
  CONFIG_HTTP_TIMEOUT_SECONDS="$HTTP_TIMEOUT_SECONDS" \
  CONFIG_ASR_TIMEOUT_SECONDS="$ASR_TIMEOUT_SECONDS" \
  CONFIG_STREAMING_ASR="$STREAMING_ASR" \
  CONFIG_SPECULATIVE_LLM="$SPECULATIVE_LLM" \
  CONFIG_FILLER_ENABLED="$FILLER_ENABLED" \
  CONFIG_FILLER_SEED="$FILLER_SEED" \
  CONFIG_QWEN_SEED="$QWEN_SEED" \
  CONFIG_MAX_TURNS="$MAX_TURNS" \
  CONFIG_MAX_LLM_TOKENS="$MAX_LLM_TOKENS" \
  CONFIG_TEMPERATURE="$TEMPERATURE" \
  CONFIG_GREETING="$GREETING" \
  CONFIG_TECHNICAL_FAILURE="$TECHNICAL_FAILURE" \
  CONFIG_COMPLETION="$COMPLETION" \
  CONFIG_SYSTEM_PROMPT="$SYSTEM_PROMPT" \
  CONFIG_TELEPHONE_OVERLAY="$TELEPHONE_OVERLAY" \
  CONFIG_CHAT_OVERLAY="$CHAT_OVERLAY" \
  CONFIG_TEXT_API_ENABLED="$TEXT_API_ENABLED" \
  CONFIG_TEXT_API_BIND="$TEXT_API_BIND" \
  CONFIG_TEXT_API_PORT="$TEXT_API_PORT" \
  CONFIG_ENERGY_THRESHOLD="$ENERGY_THRESHOLD" \
  CONFIG_PREROLL_MS="$PREROLL_MS" \
  CONFIG_SPEECH_START_MS="$SPEECH_START_MS" \
  CONFIG_SPEECH_END_MS="$SPEECH_END_MS" \
  CONFIG_MINIMUM_UTTERANCE_MS="$MINIMUM_UTTERANCE_MS" \
  CONFIG_MAXIMUM_UTTERANCE_MS="$MAXIMUM_UTTERANCE_MS" \
  CONFIG_DEBUG_ALLOW_SENSITIVE_CONSOLE="$DEBUG_ALLOW_SENSITIVE_CONSOLE" \
  CONFIG_DEBUG_METRICS_INTERVAL_MS="$DEBUG_METRICS_INTERVAL_MS" \
  CONFIG_PERFORMANCE_ENABLED="$PERFORMANCE_ENABLED" \
  CONFIG_PERFORMANCE_LOG_FILE="$PERFORMANCE_LOG_FILE" \
  CONFIG_PERFORMANCE_MAX_BYTES="$PERFORMANCE_MAX_BYTES" \
  CONFIG_PERFORMANCE_BACKUP_COUNT="$PERFORMANCE_BACKUP_COUNT" \
  CONFIG_ADMISSION_ENABLED="$ADMISSION_ENABLED" \
  CONFIG_LISTENER_HOST="$LISTENER_HOST" \
  CONFIG_LISTENER_PORT="$LISTENER_PORT" \
  CONFIG_PUBLISHER_ID="$PUBLISHER_ID" \
  CONFIG_SNAPSHOT_INTERVAL_MS="$SNAPSHOT_INTERVAL_MS" \
  CONFIG_LEASE_TTL_MS="$LEASE_TTL_MS" \
  CONFIG_CONNECT_TIMEOUT_MS="$CONNECT_TIMEOUT_MS" \
  CONFIG_ASR_PHONE_CAPACITY="$ASR_PHONE_CAPACITY" \
  /usr/bin/python3 - <<'PY'
import ipaddress
import os
import re
from urllib.parse import urlsplit

def ip(name: str) -> None:
    raw = os.environ[name]
    try:
        value = ipaddress.ip_address(raw)
    except ValueError as exc:
        raise SystemExit(f"ERROR: {name} must be a literal IP address: {raw!r}") from exc
    if value.version != 4:
        raise SystemExit(f"ERROR: {name} must be an IPv4 address in version 2.5.1")
    if value.is_unspecified or value.is_multicast:
        raise SystemExit(f"ERROR: {name} may not be unspecified or multicast")

ip("CONFIG_MAIN_HOST")
ip("CONFIG_BACKEND_BIND_IP")
ip("CONFIG_LISTENER_HOST")
for name in (
    "CONFIG_MAIN_PORT", "CONFIG_ASTERISK_BIND_PORT", "CONFIG_LISTENER_PORT"
):
    raw = os.environ[name]
    if not raw.isdigit() or not 1 <= int(raw) <= 65535:
        raise SystemExit(f"ERROR: {name} must be a port from 1 through 65535")

secret_re = re.compile(r"^[A-Za-z0-9_-]{20,128}$")
for name in ("CONFIG_PASSWORD_0", "CONFIG_PASSWORD_1", "CONFIG_PASSWORD_2"):
    if not secret_re.fullmatch(os.environ[name]):
        raise SystemExit(
            f"ERROR: {name} must contain 20-128 characters from A-Z, a-z, 0-9, '_' or '-'"
        )
if len({os.environ[f"CONFIG_PASSWORD_{i}"] for i in range(3)}) != 3:
    raise SystemExit("ERROR: The three SIP accounts must use distinct passwords")

for name, schemes in (
    ("CONFIG_ASR_URL", {"ws", "wss"}),
    ("CONFIG_LLM_URL", {"http", "https"}),
    ("CONFIG_QWEN_URL", {"http", "https"}),
    ("CONFIG_PIPER_URL", {"http", "https"}),
):
    parsed = urlsplit(os.environ[name])
    try:
        port = parsed.port
    except ValueError as exc:
        raise SystemExit(f"ERROR: Invalid service port in {name}") from exc
    if parsed.scheme not in schemes or not parsed.hostname or not parsed.path.startswith("/"):
        raise SystemExit(f"ERROR: Invalid service URL in {name}")
    if port is not None and not 1 <= port <= 65535:
        raise SystemExit(f"ERROR: Invalid service port in {name}")
    if parsed.username or parsed.password or parsed.fragment:
        raise SystemExit(f"ERROR: Credentials and fragments are not allowed in {name}")

if os.environ["CONFIG_TTS_BACKEND"] not in {"qwen", "piper"}:
    raise SystemExit("ERROR: --tts must be qwen or piper")
for name in ("CONFIG_QWEN_SPEAKER", "CONFIG_QWEN_LANGUAGE"):
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", os.environ[name]):
        raise SystemExit(f"ERROR: Invalid identifier in {name}")

if os.environ["CONFIG_ADMISSION_ENABLED"] != "true":
    raise SystemExit("ERROR: Admission must remain enabled in version 2.5.1")
if os.environ["CONFIG_DEBUG_ALLOW_SENSITIVE_CONSOLE"] not in {"true", "false"}:
    raise SystemExit("ERROR: Debug sensitive-console switch must be true or false")
if os.environ["CONFIG_STREAMING_ASR"] not in {"true", "false"}:
    raise SystemExit("ERROR: Streaming ASR switch must be true or false")
if os.environ["CONFIG_SPECULATIVE_LLM"] not in {"true", "false"}:
    raise SystemExit("ERROR: Speculative LLM switch must be true or false")
if os.environ["CONFIG_STREAMING_ASR"] != "false" or os.environ["CONFIG_SPECULATIVE_LLM"] != "false":
    raise SystemExit("ERROR: Version 2.5.1 requires block processing")
if os.environ["CONFIG_FILLER_ENABLED"] not in {"true", "false"}:
    raise SystemExit("ERROR: Filler switch must be true or false")
if os.environ["CONFIG_PERFORMANCE_ENABLED"] not in {"true", "false"}:
    raise SystemExit("ERROR: Performance logging switch must be true or false")
performance_log = os.environ["CONFIG_PERFORMANCE_LOG_FILE"]
if performance_log != "/var/log/kienzlefon-ai-asterisk-backend/performance.jsonl":
    raise SystemExit("ERROR: Performance log must use the managed JSONL path")
if os.environ["CONFIG_TEXT_API_ENABLED"] != "true":
    raise SystemExit("ERROR: Text API must remain enabled in version 2.5.1")
if os.environ["CONFIG_TEXT_API_BIND"] != "127.0.0.1":
    raise SystemExit("ERROR: Text API must bind to 127.0.0.1 in version 2.5.1")
if not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", os.environ["CONFIG_PUBLISHER_ID"]):
    raise SystemExit("ERROR: Invalid publisher identifier")

def integer(name: str, minimum: int, maximum: int) -> int:
    raw = os.environ[name]
    if not raw.isdigit() or not minimum <= int(raw) <= maximum:
        raise SystemExit(f"ERROR: {name} must be between {minimum} and {maximum}")
    return int(raw)

integer("CONFIG_HTTP_TIMEOUT_SECONDS", 1, 300)
integer("CONFIG_ASR_TIMEOUT_SECONDS", 1, 300)
integer("CONFIG_QWEN_SEED", 0, 2**31 - 1)
integer("CONFIG_FILLER_SEED", 0, 2**31 - 1)
integer("CONFIG_MAX_TURNS", 1, 50)
integer("CONFIG_MAX_LLM_TOKENS", 64, 4096)
integer("CONFIG_ENERGY_THRESHOLD", 100, 10000)
integer("CONFIG_DEBUG_METRICS_INTERVAL_MS", 100, 5000)
integer("CONFIG_PERFORMANCE_MAX_BYTES", 1048576, 1073741824)
integer("CONFIG_PERFORMANCE_BACKUP_COUNT", 1, 20)
integer("CONFIG_PREROLL_MS", 0, 2000)
integer("CONFIG_SPEECH_START_MS", 20, 2000)
integer("CONFIG_SPEECH_END_MS", 100, 5000)
minimum_utterance = integer("CONFIG_MINIMUM_UTTERANCE_MS", 20, 10000)
maximum_utterance = integer("CONFIG_MAXIMUM_UTTERANCE_MS", 1000, 120000)
if minimum_utterance >= maximum_utterance:
    raise SystemExit("ERROR: Minimum utterance duration must be below maximum")
snapshot_interval = integer("CONFIG_SNAPSHOT_INTERVAL_MS", 250, 5000)
lease_ttl = integer("CONFIG_LEASE_TTL_MS", 1000, 30000)
if snapshot_interval * 2 >= lease_ttl:
    raise SystemExit("ERROR: Lease TTL must exceed two snapshot intervals")
integer("CONFIG_CONNECT_TIMEOUT_MS", 100, 10000)
integer("CONFIG_ASR_PHONE_CAPACITY", 1, 3)
text_api_port = integer("CONFIG_TEXT_API_PORT", 1024, 65535)
reserved_ports = {
    int(os.environ[name])
    for name in ("CONFIG_MAIN_PORT", "CONFIG_ASTERISK_BIND_PORT", "CONFIG_LISTENER_PORT")
}
reserved_ports.update({8290, 8291, 8292})
if text_api_port in reserved_ports:
    raise SystemExit("ERROR: Text API port conflicts with a configured runtime port")
try:
    temperature = float(os.environ["CONFIG_TEMPERATURE"])
except ValueError as exc:
    raise SystemExit("ERROR: Invalid LLM temperature") from exc
if not 0.0 <= temperature <= 2.0:
    raise SystemExit("ERROR: LLM temperature must be between 0 and 2")

for name, maximum in (
    ("CONFIG_GREETING", 1000),
    ("CONFIG_TECHNICAL_FAILURE", 1000),
    ("CONFIG_COMPLETION", 1000),
    ("CONFIG_SYSTEM_PROMPT", 32000),
    ("CONFIG_TELEPHONE_OVERLAY", 32000),
    ("CONFIG_CHAT_OVERLAY", 32000),
):
    value = os.environ[name].strip()
    if not value or len(value) > maximum or "\x00" in value:
        raise SystemExit(f"ERROR: Invalid text in {name}")
    if any(ord(char) < 32 and char not in "\t\n" for char in value):
        raise SystemExit(f"ERROR: Control character in {name}")
PY
}

verify_local_bind_ip() {
  ip -j address show | /usr/bin/python3 -c '
import ipaddress, json, os, sys
expected = ipaddress.ip_address(os.environ["EXPECTED_BIND_IP"])
data = json.load(sys.stdin)
available = {
    ipaddress.ip_address(info["local"])
    for interface in data
    for info in interface.get("addr_info", [])
    if "local" in info
}
if expected not in available:
    raise SystemExit(f"ERROR: Backend bind IP {expected} is not configured on this host")
'
}

toml_quote() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"
}

toml_multiline_quote() {
  /usr/bin/python3 -c '
import sys
value = sys.argv[1].replace("\\", "\\\\").replace("\"", "\\\"")
print("\"\"\"\\\n" + value + "\\\n\"\"\"")
' "$1"
}

write_backend_config() {
  local target="$1"
  install -d -m 0750 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  {
    printf '# Kienzlefon AI Asterisk Backend\n'
    printf '# Version: 2.5.1\n\n'
    printf '[backend]\n'
    printf 'version = "2.5.1"\n'
    printf 'slot_count = 3\n'
    printf 'first_audio_port = %s\n' "$FIRST_AUDIO_PORT"
    printf 'runtime_directory = %s\n' "$(toml_quote "$RUNTIME_DIR")"
    printf 'state_directory = %s\n' "$(toml_quote "$STATE_DIR")"
    printf 'kienzlefon_config = %s\n' "$(toml_quote "$KIENZLEFON_CONFIG")"
    printf 'kienzlefon_python = %s\n\n' "$(toml_quote "$KIENZLEFON_PYTHON")"
    printf '[sip]\n'
    printf 'main_host = %s\n' "$(toml_quote "$MAIN_HOST")"
    printf 'main_port = %s\n' "$MAIN_PORT"
    printf 'backend_bind_ip = %s\n' "$(toml_quote "$BACKEND_BIND_IP")"
    printf 'backend_bind_port = %s\n' "$ASTERISK_BIND_PORT"
    printf 'extensions = ["8810", "8811", "8812"]\n'
    printf 'slot_ids = ["ai-slot-00", "ai-slot-01", "ai-slot-02"]\n'
    printf 'passwords = [%s, %s, %s]\n\n' \
      "$(toml_quote "$SIP_PASSWORD_0")" \
      "$(toml_quote "$SIP_PASSWORD_1")" \
      "$(toml_quote "$SIP_PASSWORD_2")"
    printf '[services]\n'
    printf 'asr_url = %s\n' "$(toml_quote "$ASR_URL")"
    printf 'llm_url = %s\n' "$(toml_quote "$LLM_URL")"
    printf 'qwen_url = %s\n' "$(toml_quote "$QWEN_URL")"
    printf 'piper_url = %s\n' "$(toml_quote "$PIPER_URL")"
    printf 'http_timeout_seconds = %s\n' "$HTTP_TIMEOUT_SECONDS"
    printf 'asr_timeout_seconds = %s\n\n' "$ASR_TIMEOUT_SECONDS"
    printf '[dialog]\n'
    printf '# Version 2.5.1: complete utterance first; no speculative LLM.\n'
    printf 'streaming_asr = %s\n' "$STREAMING_ASR"
    printf 'speculative_llm = %s\n' "$SPECULATIVE_LLM"
    printf 'tts_backend = %s\n' "$(toml_quote "$TTS_BACKEND")"
    printf 'qwen_speaker = %s\n' "$(toml_quote "$QWEN_SPEAKER")"
    printf 'qwen_language = %s\n' "$(toml_quote "$QWEN_LANGUAGE")"
    printf 'qwen_seed = %s\n' "$QWEN_SEED"
    printf 'max_turns = %s\n' "$MAX_TURNS"
    printf 'max_llm_tokens = %s\n' "$MAX_LLM_TOKENS"
    printf 'temperature = %s\n' "$TEMPERATURE"
    printf 'greeting = %s\n' "$(toml_quote "$GREETING")"
    printf 'technical_failure = %s\n' "$(toml_quote "$TECHNICAL_FAILURE")"
    printf 'completion = %s\n' "$(toml_quote "$COMPLETION")"
    printf 'system_prompt = %s\n' "$(toml_multiline_quote "$SYSTEM_PROMPT")"
    printf 'telephone_overlay = %s\n' "$(toml_multiline_quote "$TELEPHONE_OVERLAY")"
    printf 'chat_overlay = %s\n\n' "$(toml_multiline_quote "$CHAT_OVERLAY")"
    printf '[filler]\n'
    printf '# Independent of dialog.qwen_seed; changing live TTS leaves cached clips valid.\n'
    printf 'seed = %s\n' "$FILLER_SEED"
    # JSON is data only; never eval user-configured announcement text in a shell.
    FILLER_OPTIONS="$FILLER_OPTIONS" python3 - <<'PY'
import json, os
values = json.loads(os.environ["FILLER_OPTIONS"])
defaults = {
    "regenerate_on_reload": True,
    "part1_text": "Bitte warten.", "part1_start_ms": 2000,
    "part2_text": "Ich verarbeite.", "part2_start_ms": 7000,
    "part3_text": "Bitte warten.", "part3_start_ms": 13000,
    "beep_enabled": True, "beep_start_ms": 0, "beep_interval_ms": 1000,
    "beep_frequency_hz": 400, "beep_duration_ms": 100, "beep_volume": 0.15,
}
print("# Absolute start times from detected speech end; empty text disables a part.")
for key, default in defaults.items():
    print(f"{key} = {json.dumps(values.get(key, default), ensure_ascii=True)}")
PY
    printf '# No TTS during calls; changed clips are prepared on explicit idle reload.\n'
    printf 'enabled = %s\n\n' "$FILLER_ENABLED"
    printf '[text_api]\n'
    printf 'enabled = %s\n' "$TEXT_API_ENABLED"
    printf 'bind = %s\n' "$(toml_quote "$TEXT_API_BIND")"
    printf 'port = %s\n\n' "$TEXT_API_PORT"
    printf '[vad]\n'
    printf 'energy_threshold = %s\n' "$ENERGY_THRESHOLD"
    printf 'preroll_ms = %s\n' "$PREROLL_MS"
    printf 'speech_start_ms = %s\n' "$SPEECH_START_MS"
    printf 'speech_end_ms = %s\n' "$SPEECH_END_MS"
    printf 'minimum_utterance_ms = %s\n' "$MINIMUM_UTTERANCE_MS"
    printf 'maximum_utterance_ms = %s\n\n' "$MAXIMUM_UTTERANCE_MS"
    printf '[debug]\n'
    printf '# Sensitive text is never logged; this permits only an explicit root live console.\n'
    printf 'allow_sensitive_console = %s\n' "$DEBUG_ALLOW_SENSITIVE_CONSOLE"
    printf 'metrics_interval_ms = %s\n\n' "$DEBUG_METRICS_INTERVAL_MS"
    printf '[performance]\n'
    printf '# Technical timing data only; never audio, transcript, prompt or response text.\n'
    printf 'enabled = %s\n' "$PERFORMANCE_ENABLED"
    printf 'log_file = %s\n' "$(toml_quote "$PERFORMANCE_LOG_FILE")"
    printf 'max_bytes = %s\n' "$PERFORMANCE_MAX_BYTES"
    printf 'backup_count = %s\n\n' "$PERFORMANCE_BACKUP_COUNT"
    printf '[admission]\n'
    printf 'enabled = %s\n' "$ADMISSION_ENABLED"
    printf 'listener_host = %s\n' "$(toml_quote "$LISTENER_HOST")"
    printf 'listener_port = %s\n' "$LISTENER_PORT"
    printf 'publisher_id = %s\n' "$(toml_quote "$PUBLISHER_ID")"
    printf 'snapshot_interval_ms = %s\n' "$SNAPSHOT_INTERVAL_MS"
    printf 'lease_ttl_ms = %s\n' "$LEASE_TTL_MS"
    printf 'connect_timeout_ms = %s\n' "$CONNECT_TIMEOUT_MS"
    printf 'control_socket = %s\n' "$(toml_quote "$CAPACITY_CONTROL_SOCKET")"
    printf 'asr_phone_capacity = %s\n' "$ASR_PHONE_CAPACITY"
  } >"$temp"
  chmod 0640 "$temp"
  mv -f "$temp" "$target"
}

write_pjsip_config() {
  local target="$1" p0 p1 p2
  p0="$SIP_PASSWORD_0"; p1="$SIP_PASSWORD_1"; p2="$SIP_PASSWORD_2"
  install -d -m 0750 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<EOF
; Kienzlefon AI Asterisk Backend
; Version: 2.5.1
; Generated configuration. Three fixed SIP clients, no provider routes.

[global]
type=global
user_agent=Kienzlefon-AI-Asterisk-Backend/2.5.1

[system]
type=system
timer_t1=500
timer_b=32000

[transport-kienzlefon-ai]
type=transport
protocol=udp
bind=${BACKEND_BIND_IP}:${ASTERISK_BIND_PORT}
allow_reload=yes

$(render_pjsip_slot 0 "$p0")

$(render_pjsip_slot 1 "$p1")

$(render_pjsip_slot 2 "$p2")
EOF
  chmod 0640 "$temp"
  mv -f "$temp" "$target"
}

render_pjsip_slot() {
  local index="$1" password="$2" extension slot
  extension=$((FIRST_EXTENSION + index))
  printf -v slot 'ai-slot-%02d' "$index"
  cat <<EOF
[${slot}-registration]
type=registration
transport=transport-kienzlefon-ai
outbound_auth=${slot}-auth
server_uri=sip:${MAIN_HOST}:${MAIN_PORT}
client_uri=sip:${extension}@${MAIN_HOST}:${MAIN_PORT}
contact_user=${extension}
retry_interval=10
forbidden_retry_interval=60
fatal_retry_interval=60
expiration=120
max_retries=100000
auth_rejection_permanent=no
line=yes
endpoint=${slot}-endpoint

[${slot}-auth]
type=auth
auth_type=userpass
username=${extension}
password=${password}

[${slot}-aor]
type=aor
contact=sip:${MAIN_HOST}:${MAIN_PORT}
qualify_frequency=10
qualify_timeout=2.0

[${slot}-endpoint]
type=endpoint
transport=transport-kienzlefon-ai
context=kienzlefon-ai-slot-${index}-in
disallow=all
allow=g722,alaw,ulaw
outbound_auth=${slot}-auth
aors=${slot}-aor
from_user=${extension}
from_domain=${MAIN_HOST}
direct_media=no
rewrite_contact=yes
rtp_symmetric=yes
force_rport=yes
trust_id_inbound=no
trust_id_outbound=no
send_pai=no
send_rpid=no
device_state_busy_at=1
EOF
}

write_extensions_config() {
  local target="$1"
  install -d -m 0750 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<EOF
; Kienzlefon AI Asterisk Backend
; Version: 2.5.1
; Incoming calls are accepted only after local guard validation.

[general]
static=yes
writeprotect=yes
clearglobalvars=no

[globals]
KZF_AI_AGENT=${AGENT_PATH}
KZF_AI_BACKEND_CONFIG=${CONFIG_FILE}

$(render_extension_slot 0)

$(render_extension_slot 1)

$(render_extension_slot 2)

[default]
exten => _X.,1,Hangup(21)
exten => s,1,Hangup(21)
EOF
  chmod 0640 "$temp"
  mv -f "$temp" "$target"
}

render_extension_slot() {
  local index="$1" slot extension port
  extension=$((FIRST_EXTENSION + index))
  port=$((FIRST_AUDIO_PORT + index))
  printf -v slot 'ai-slot-%02d' "$index"
  cat <<EOF
[kienzlefon-ai-slot-${index}-in]
exten => _X.,1,NoOp(Kienzlefon AI ${slot})
 same => n,Set(CHANNEL(language)=de)
 same => n,Set(KZF_AI_PROTOCOL=\${PJSIP_HEADER(read,X-Kienzlefon-Protocol)})
 same => n,Set(KZF_AI_REQUEST_ID=\${PJSIP_HEADER(read,X-Kienzlefon-Request-ID)})
 same => n,Set(KZF_AI_LEASE_ID=\${PJSIP_HEADER(read,X-Kienzlefon-Lease-ID)})
 same => n,Set(KZF_AI_HEADER_SLOT=\${PJSIP_HEADER(read,X-Kienzlefon-Slot-ID)})
 same => n,Set(KZF_AI_CALL_UUID=\${UUID()})
 same => n,AGI(\${KZF_AI_AGENT},guard,--config,\${KZF_AI_BACKEND_CONFIG},--slot-index,${index})
 same => n,GotoIf(\$["\${KZF_AI_GUARD_ACCEPTED}"="1"]?accepted:rejected)
 same => n(rejected),Hangup(21)
 same => n(accepted),Answer()
 same => n,Dial(AudioSocket/127.0.0.1:${port}/\${KZF_AI_CALL_UUID}/c(slin16))
 same => n,Hangup()
exten => s,1,Goto(${extension},1)
EOF
}

write_systemd_unit() {
  local target="$1" spool_path="$2" output_path="$3" asterisk_group="${4:-root}"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<EOF
# Kienzlefon AI Asterisk Backend agent
# Version: 2.5.1

[Unit]
Description=Kienzlefon AI telephone agent slot %i
After=network-online.target asterisk.service kienzlefon-ai-capacity-publisher.service
Wants=network-online.target kienzlefon-ai-capacity-publisher.service
Requires=asterisk.service
PartOf=asterisk.service

[Service]
Type=simple
User=root
Group=${asterisk_group}
UMask=0027
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 ${AGENT_PATH} serve --config ${CONFIG_FILE} --slot-index %i
Restart=on-failure
RestartSec=2
TimeoutStopSec=15
KillSignal=SIGTERM
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=${RUNTIME_DIR}/slot-%i ${STATE_DIR} ${PERFORMANCE_LOG_DIR} ${spool_path} ${output_path}
RuntimeDirectory=kienzlefon-ai-asterisk-backend/slot-%i
RuntimeDirectoryMode=0750
StateDirectory=kienzlefon-ai-asterisk-backend
StateDirectoryMode=0750
LogsDirectory=kienzlefon-ai-asterisk-backend
LogsDirectoryMode=0750

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$temp"
  mv -f "$temp" "$target"
}

write_capacity_systemd_unit() {
  local target="$1" asterisk_group="${2:-root}"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<EOF
# Kienzlefon AI capacity publisher
# Version: 2.5.1

[Unit]
Description=Kienzlefon AI capacity publisher
After=network-online.target
Wants=network-online.target
Before=kienzlefon-ai-agent@0.service kienzlefon-ai-agent@1.service kienzlefon-ai-agent@2.service

[Service]
Type=simple
User=root
Group=${asterisk_group}
UMask=0007
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 ${CAPACITY_PATH} --config ${CONFIG_FILE}
Restart=always
RestartSec=2
TimeoutStopSec=10
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=/run/kienzlefon-ai-integration
RuntimeDirectory=kienzlefon-ai-integration
RuntimeDirectoryMode=0770

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$temp"
  mv -f "$temp" "$target"
}

write_text_systemd_unit() {
  local target="$1" spool_path="$2" output_path="$3"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<EOF
# Kienzlefon AI local text and persistent chat interface
# Version: 2.5.1

[Unit]
Description=Kienzlefon AI local text and persistent chat interface
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
UMask=0077
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 ${AGENT_PATH} serve-text --config ${CONFIG_FILE}
Restart=on-failure
RestartSec=2
TimeoutStopSec=10
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=${RUNTIME_DIR}/text ${STATE_DIR} ${spool_path} ${output_path}
RuntimeDirectory=kienzlefon-ai-asterisk-backend/text
RuntimeDirectoryMode=0700
StateDirectory=kienzlefon-ai-asterisk-backend
StateDirectoryMode=0750

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$temp"
  mv -f "$temp" "$target"
}

write_reload_command() {
  local target="$1"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<'PY'
#!/usr/bin/env python3
"""Validate and safely reload Kienzlefon AI runtime services."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path
from typing import Any, Mapping

CONFIG = Path("/etc/kienzlefon-ai-asterisk-backend/backend.toml")
AGENT = Path("/opt/kienzlefon-ai-asterisk-backend/bin/kienzlefon_ai_agent.py")
PUBLISHER = Path("/opt/kienzlefon-ai-asterisk-backend/bin/kienzlefon_ai_capacity_publisher.py")
CONTROL_PROTOCOL = "kienzlefon-ai-capacity-control-v1"
CAPACITY_SERVICE = "kienzlefon-ai-capacity-publisher.service"
TEXT_SERVICE = "kienzlefon-ai-text.service"
AGENT_SERVICES = tuple(f"kienzlefon-ai-agent@{index}.service" for index in range(3))
STATE = Path("/var/lib/kienzlefon-ai-asterisk-backend")
LAST_GOOD = STATE / "last-reload.toml"
FILLER = Path("/opt/kienzlefon-ai-asterisk-backend/audio/filler-v1")
FILLER_FILES = ("01-bitte-warten.pcm", "02-ich-verarbeite.pcm", "03-bitte-warten.pcm", "manifest.json")
BACKUPS = Path("/var/backups/kienzlefon-ai-asterisk-backend")


class ReloadError(RuntimeError):
    pass


def run_checked(arguments: list[str], timeout: float = 20.0) -> None:
    result = subprocess.run(arguments, check=False, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        raise ReloadError("command_failed")


def unix_command(path: Path, message: Mapping[str, Any]) -> Mapping[str, Any]:
    body = json.dumps(message, separators=(",", ":")).encode() + b"\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(5.0)
        client.connect(str(path))
        client.sendall(body)
        response = bytearray()
        while not response.endswith(b"\n"):
            if len(response) > 65_536:
                raise ReloadError("control_response_too_large")
            block = client.recv(4096)
            if not block:
                raise ReloadError("control_response_closed")
            response.extend(block)
    value = json.loads(response)
    if not isinstance(value, Mapping):
        raise ReloadError("control_response_invalid")
    return value


def load_paths() -> tuple[tuple[str, ...], tuple[Path, ...], Path]:
    with CONFIG.open("rb") as handle:
        raw = tomllib.load(handle)
    backend = raw["backend"]
    sip = raw["sip"]
    admission = raw["admission"]
    slot_ids = tuple(str(value) for value in sip["slot_ids"])
    if slot_ids != ("ai-slot-00", "ai-slot-01", "ai-slot-02"):
        raise ReloadError("slot_configuration_invalid")
    runtime = Path(str(backend["runtime_directory"]))
    agent_sockets = tuple(runtime / f"slot-{index}" / "control.sock" for index in range(3))
    capacity_socket = Path(str(admission["control_socket"]))
    if not capacity_socket.is_absolute() or any(not path.is_absolute() for path in agent_sockets):
        raise ReloadError("control_path_invalid")
    return slot_ids, agent_sockets, capacity_socket


def validate_configuration() -> tuple[tuple[str, ...], tuple[Path, ...], Path]:
    if not CONFIG.is_file() or not AGENT.is_file() or not PUBLISHER.is_file():
        raise ReloadError("installation_incomplete")
    run_checked([sys.executable, str(AGENT), "check-config", "--config", str(CONFIG)])
    run_checked([sys.executable, str(PUBLISHER), "--config", str(CONFIG), "--check-config"])
    return load_paths()


def agent_statuses(agent_sockets: tuple[Path, ...]) -> list[Mapping[str, Any]]:
    statuses = []
    for path in agent_sockets:
        response = unix_command(path, {"command": "status"})
        if response.get("ok") is not True:
            raise ReloadError("agent_status_rejected")
        statuses.append(response)
    return statuses


def capacity_status(capacity_socket: Path) -> Mapping[str, Any]:
    response = unix_command(capacity_socket, {
        "protocol": CONTROL_PROTOCOL,
        "command": "status",
    })
    if response.get("accepted") is not True:
        raise ReloadError("publisher_status_rejected")
    return response


def ensure_idle(statuses: list[Mapping[str, Any]]) -> None:
    busy = [status.get("slot_id", "unknown") for status in statuses if status.get("state") != "idle"]
    if busy:
        raise ReloadError("active_or_reserved_calls")


def inspect(agent_sockets: tuple[Path, ...], capacity_socket: Path) -> None:
    statuses = agent_statuses(agent_sockets)
    publisher = capacity_status(capacity_socket)
    if not all(status.get("sip_registered") is True for status in statuses):
        raise ReloadError("sip_not_registered")
    if (
        publisher.get("listener_connected") is not True
        or publisher.get("last_snapshot_accepted") is not True
    ):
        raise ReloadError("listener_not_connected")
    busy = sum(status.get("state") != "idle" for status in statuses)
    print(
        "CHECK_OK slots=3 sip_registered=3 listener_connected=true "
        f"free_slots={int(publisher.get('free_slots', 0))} busy_slots={busy}"
    )


def withdraw(slot_ids: tuple[str, ...], capacity_socket: Path) -> None:
    for slot_id in slot_ids:
        response = unix_command(capacity_socket, {
            "protocol": CONTROL_PROTOCOL,
            "command": "set_slot_state",
            "slot_id": slot_id,
            "state": "not_ready",
            "reason": "maintenance",
        })
        if response.get("accepted") is not True:
            raise ReloadError("capacity_withdraw_rejected")


def wait_until_withdrawn(capacity_socket: Path) -> None:
    deadline = time.monotonic() + 7.0
    while time.monotonic() < deadline:
        status = capacity_status(capacity_socket)
        if status.get("last_snapshot_accepted") is True and int(status.get("free_slots", -1)) == 0:
            return
        time.sleep(0.1)
    raise ReloadError("capacity_withdraw_timeout")


def reload_services(
    slot_ids: tuple[str, ...], agent_sockets: tuple[Path, ...], capacity_socket: Path,
    update: Any = None,
) -> None:
    statuses = agent_statuses(agent_sockets)
    ensure_idle(statuses)
    publisher = capacity_status(capacity_socket)
    slots = publisher.get("slots")
    if not isinstance(slots, Mapping):
        raise ReloadError("publisher_slots_invalid")
    if any(not isinstance(slots.get(slot_id), Mapping) for slot_id in slot_ids):
        raise ReloadError("publisher_slots_incomplete")
    if any(
        isinstance(slots.get(slot_id), Mapping)
        and slots[slot_id].get("state") in {"in_call", "draining"}
        for slot_id in slot_ids
    ):
        raise ReloadError("publisher_reports_busy_slot")
    if update is not None:
        update.verify_unchanged()
        update.services_touched = True
    run_checked(["/usr/bin/systemctl", "stop", *AGENT_SERVICES], timeout=30.0)
    withdraw(slot_ids, capacity_socket)
    wait_until_withdrawn(capacity_socket)
    if update is not None:
        update.activate()
    start_services(agent_sockets, capacity_socket)


def start_services(agent_sockets: tuple[Path, ...], capacity_socket: Path) -> None:
    run_checked(["/usr/bin/systemctl", "restart", CAPACITY_SERVICE], timeout=30.0)
    deadline = time.monotonic() + 20.0
    while time.monotonic() < deadline:
        if capacity_socket.exists():
            try:
                capacity_status(capacity_socket)
                break
            except Exception:
                pass
        time.sleep(0.25)
    else:
        raise ReloadError("publisher_start_timeout")
    run_checked(["/usr/bin/systemctl", "restart", *AGENT_SERVICES], timeout=30.0)
    run_checked(["/usr/bin/systemctl", "restart", TEXT_SERVICE], timeout=30.0)
    deadline = time.monotonic() + 45.0
    last_reason = "readiness_timeout"
    while time.monotonic() < deadline:
        try:
            statuses = agent_statuses(agent_sockets)
            publisher = capacity_status(capacity_socket)
            if (
                all(status.get("state") == "idle" for status in statuses)
                and all(status.get("sip_registered") is True for status in statuses)
                and publisher.get("listener_connected") is True
                and publisher.get("last_snapshot_accepted") is True
                and int(publisher.get("free_slots", 0)) == 3
            ):
                return
            last_reason = "not_all_slots_free"
        except Exception as error:
            last_reason = str(error) or type(error).__name__
        time.sleep(0.5)
    raise ReloadError(last_reason)


def regular(path: Path, optional: bool = False) -> None:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ReloadError("unsafe_managed_file")
    if not optional and not path.is_file():
        raise ReloadError("managed_file_missing")


def atomic_write(path: Path, body: bytes, mode: int, uid: int = 0, gid: int = 0) -> None:
    regular(path, optional=True)
    fd, name = tempfile.mkstemp(prefix=".reload-", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(body)
            os.fchown(handle.fileno(), uid, gid)
            os.fchmod(handle.fileno(), mode)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


class FillerUpdate:
    """Prepare first; publish only after idle recheck; roll back files/config on failure."""
    def __init__(self, stage: Path) -> None:
        self.stage = stage
        self.services_touched = False
        self.assets_touched = False
        self.backup: Path | None = None
        for directory in (STATE, BACKUPS, FILLER.parent.parent):
            if not directory.is_dir() or directory.resolve() != directory:
                raise ReloadError("unsafe_managed_directory")
        if FILLER.parent.is_symlink() or (FILLER.parent.exists() and not FILLER.parent.is_dir()):
            raise ReloadError("unsafe_filler_parent")
        if FILLER.is_symlink() or (FILLER.exists() and not FILLER.is_dir()):
            raise ReloadError("unsafe_filler_directory")
        regular(CONFIG)
        regular(LAST_GOOD)
        if CONFIG.stat().st_size > 1_048_576 or LAST_GOOD.stat().st_size > 1_048_576:
            raise ReloadError("configuration_too_large")
        self.desired = CONFIG.read_bytes()
        self.previous = LAST_GOOD.read_bytes()
        self.config_metadata = CONFIG.stat()
        run_checked([sys.executable, str(AGENT), "check-config", "--config", str(LAST_GOOD)])
        self.old_assets = {}
        for name in FILLER_FILES:
            path = FILLER / name
            regular(path, optional=True)
            if path.exists() and path.stat().st_size > 400000:
                raise ReloadError("filler_file_too_large")
            self.old_assets[name] = path.read_bytes() if path.exists() else None
        atomic_write(stage / "candidate.toml", self.desired, 0o600)
        raw = tomllib.loads(self.desired.decode())
        filler = raw.get("filler", {})
        self.new_assets: dict[str, bytes] = {}
        if filler.get("enabled", True):
            if filler.get("regenerate_on_reload", True):
                timeout = 30 + 3 * float(raw["services"]["http_timeout_seconds"])
                run_checked([sys.executable, str(AGENT), "prepare-filler", "--config",
                             str(stage / "candidate.toml"), "--filler-output", str(stage / "audio")], timeout=timeout)
                self.new_assets = {name: (stage / "audio" / name).read_bytes() for name in FILLER_FILES}
            else:
                run_checked([sys.executable, str(AGENT), "check-filler", "--config", str(stage / "candidate.toml")])
        self.verify_unchanged()

    def verify_unchanged(self) -> None:
        regular(CONFIG)
        regular(LAST_GOOD)
        if CONFIG.read_bytes() != self.desired or LAST_GOOD.read_bytes() != self.previous:
            raise ReloadError("configuration_changed_during_reload")
        for name, saved in self.old_assets.items():
            path = FILLER / name
            regular(path, optional=True)
            if (path.read_bytes() if path.exists() else None) != saved:
                raise ReloadError("clips_changed_during_reload")

    def activate(self) -> None:
        self.verify_unchanged()
        self.backup = Path(tempfile.mkdtemp(prefix="filler-reload-2.5.1-", dir=BACKUPS))
        atomic_write(self.backup / "previous.toml", self.previous, 0o600)
        atomic_write(self.backup / "requested.toml", self.desired, 0o600)
        for name, body in self.old_assets.items():
            if body is not None:
                atomic_write(self.backup / name, body, 0o600)
        if self.new_assets:
            FILLER.parent.mkdir(mode=0o755, exist_ok=True)
            FILLER.mkdir(mode=0o755, exist_ok=True)
            self.assets_touched = True
            for name, body in self.new_assets.items():
                atomic_write(FILLER / name, body, 0o644)

    def finish(self) -> None:
        if CONFIG.read_bytes() != self.desired:
            raise ReloadError("configuration_changed_during_reload")
        atomic_write(LAST_GOOD, self.desired, 0o600)

    def rollback(self) -> None:
        if self.assets_touched:
            for name, body in self.old_assets.items():
                path = FILLER / name
                if body is None:
                    regular(path, optional=True)
                    path.unlink(missing_ok=True)
                else:
                    atomic_write(path, body, 0o644)
        # Never overwrite a concurrent administrator edit with our snapshot.
        if CONFIG.read_bytes() != self.desired:
            raise ReloadError("rollback_requires_config_review")
        info = self.config_metadata
        atomic_write(CONFIG, self.previous, stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid)
        atomic_write(LAST_GOOD, self.previous, 0o600)


def reload_with_feedback(slot_ids: tuple[str, ...], sockets: tuple[Path, ...], capacity: Path) -> None:
    if not STATE.is_dir() or STATE.resolve() != STATE:
        raise ReloadError("unsafe_state_directory")
    lock_path = STATE / "filler-reload.lock"
    regular(lock_path, optional=True)
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ReloadError("reload_already_running") from None
        ensure_idle(agent_statuses(sockets))
        # Preparation failures leave the original running processes and files intact.
        with tempfile.TemporaryDirectory(prefix="filler-stage-", dir=STATE) as temporary:
            update = FillerUpdate(Path(temporary))
            try:
                reload_services(slot_ids, sockets, capacity, update)
                update.finish()
            except Exception:
                if update.services_touched:
                    run_checked(["/usr/bin/systemctl", "stop", *AGENT_SERVICES, TEXT_SERVICE])
                    update.rollback()
                    start_services(sockets, capacity)
                    print("RELOAD_ROLLBACK_OK previous_configuration_restored=true")
                raise
        print("RELOAD_OK slots=3 sip_registered=3 free_slots=3")


def feedback_reload_self_test() -> None:
    from unittest.mock import patch
    real_reload_services = reload_services
    with tempfile.TemporaryDirectory(prefix="filler-reload-test-") as temporary:
        root = Path(temporary).resolve()
        state, backups, filler = root / "state", root / "backups", root / "audio" / "filler"
        for directory in (state, backups, filler):
            directory.mkdir(parents=True)
        config, last = root / "backend.toml", state / "last-reload.toml"
        previous = b'[services]\nhttp_timeout_seconds = 5\n[filler]\nenabled = true\nseed = 42\n'
        desired = previous.replace(b'seed = 42', b'seed = 12345')
        paths = dict(STATE=state, BACKUPS=backups, FILLER=filler, CONFIG=config, LAST_GOOD=last)
        old = {name: b"old-" + name.encode() for name in FILLER_FILES}
        commands: list[list[str]] = []
        restarted: list[bool] = []
        def reset() -> None:
            config.write_bytes(desired)
            last.write_bytes(previous)
            for name, body in old.items():
                (filler / name).write_bytes(body)
            commands.clear()
            restarted.clear()
        def command(args: list[str], timeout: float = 20) -> None:
            commands.append(args)
            if "prepare-filler" in args:
                output = Path(args[-1])
                output.mkdir()
                for name in FILLER_FILES:
                    (output / name).write_bytes(b"new-" + name.encode())
        def activate(_ids: Any, _sockets: Any, _capacity: Any, update: Any) -> None:
            update.verify_unchanged()
            update.services_touched = True
            update.activate()
        with patch.dict(globals(), **paths, run_checked=command,
                        agent_statuses=lambda _: [{"state": "idle"}],
                        reload_services=activate, start_services=lambda *_: restarted.append(True)), \
                patch.object(os, "fchown", lambda *_: None):
            reset()
            reload_with_feedback((), (), root / "socket")
            assert config.read_bytes() == last.read_bytes() == desired
            assert all((filler / name).read_bytes().startswith(b"new-") for name in FILLER_FILES)
            assert len(list(backups.iterdir())) == 1
            saved = next(backups.iterdir())
            assert stat.S_IMODE(saved.stat().st_mode) == 0o700
            assert stat.S_IMODE((saved / "previous.toml").stat().st_mode) == 0o600
            assert (saved / "previous.toml").read_bytes() == previous
            assert stat.S_IMODE(last.stat().st_mode) == 0o600
            reset()
            with patch.dict(globals(), agent_statuses=lambda _: [{"state": "in_call"}]):
                try:
                    reload_with_feedback((), (), root / "socket")
                except ReloadError:
                    pass
                else:
                    raise AssertionError("busy maintenance allowed")
            assert not commands and config.read_bytes() == desired
            reset()
            arrivals = iter(([{"state": "idle"}], [{"state": "reserved"}]))
            with patch.dict(globals(), agent_statuses=lambda _: next(arrivals),
                            reload_services=real_reload_services):
                try:
                    reload_with_feedback((), (), root / "socket")
                except ReloadError as error:
                    assert str(error) == "active_or_reserved_calls"
                else:
                    raise AssertionError("call arriving during preparation was interrupted")
            assert any("prepare-filler" in args for args in commands)
            assert not any("systemctl" in args[0] for args in commands)
            assert old == {name: (filler / name).read_bytes() for name in FILLER_FILES}
            reset()
            # A second reload cannot enter while the maintenance lock is held.
            with (state / "filler-reload.lock").open("a") as held:
                fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
                try:
                    reload_with_feedback((), (), root / "socket")
                except ReloadError as error:
                    assert str(error) == "reload_already_running"
                else:
                    raise AssertionError("concurrent maintenance allowed")
            reset()
            def fail_prepare(args: list[str], timeout: float = 20) -> None:
                if "prepare-filler" in args:
                    raise ReloadError("synthetic_generation_failure")
                command(args, timeout)
            with patch.dict(globals(), run_checked=fail_prepare):
                try:
                    reload_with_feedback((), (), root / "socket")
                except ReloadError:
                    pass
                else:
                    raise AssertionError("generation failure ignored")
            assert not restarted and config.read_bytes() == desired and last.read_bytes() == previous
            assert old == {name: (filler / name).read_bytes() for name in FILLER_FILES}
            # Partial asset installation and failed restart both restore last-good config/audio.
            for failure in ("write", "restart"):
                reset()
                atomic = atomic_write
                failed = False
                def maybe_fail(path: Path, body: bytes, *args: Any) -> None:
                    nonlocal failed
                    if failure == "write" and path == filler / FILLER_FILES[1] and not failed:
                        failed = True
                        raise OSError("synthetic_write_failure")
                    atomic(path, body, *args)
                def fail_restart(ids: Any, sockets: Any, capacity: Any, update: Any) -> None:
                    activate(ids, sockets, capacity, update)
                    raise ReloadError("synthetic_readiness_failure")
                with patch.dict(globals(), atomic_write=maybe_fail,
                                reload_services=fail_restart if failure == "restart" else activate):
                    try:
                        reload_with_feedback((), (), root / "socket")
                    except (OSError, ReloadError):
                        pass
                    else:
                        raise AssertionError("activation failure ignored")
                assert old == {name: (filler / name).read_bytes() for name in FILLER_FILES}
                assert config.read_bytes() == last.read_bytes() == previous and restarted == [True]
            reset()
            config.write_bytes(desired + b'regenerate_on_reload = false\n')
            reload_with_feedback((), (), root / "socket")
            assert not any("prepare-filler" in command for command in commands)
            assert any("check-filler" in command for command in commands)
            assert old == {name: (filler / name).read_bytes() for name in FILLER_FILES}
            reset()
            def concurrent_edit(args: list[str], timeout: float = 20) -> None:
                command(args, timeout)
                config.write_bytes(desired + b"# concurrent edit\n")
            with patch.dict(globals(), run_checked=concurrent_edit):
                try:
                    reload_with_feedback((), (), root / "socket")
                except ReloadError:
                    pass
                else:
                    raise AssertionError("concurrent config edit ignored")
            assert config.read_bytes().endswith(b"# concurrent edit\n") and not restarted
            assert old == {name: (filler / name).read_bytes() for name in FILLER_FILES}
            reset()
            with patch.object(sys, "argv", ["reload", "--check"]), \
                    patch.object(os, "geteuid", lambda: 0), \
                    patch.dict(globals(), validate_configuration=lambda: ((), (), root / "socket"),
                               inspect=lambda *_: None):
                assert main() == 0
            assert not any("prepare-filler" in args or "systemctl" in args[0] for args in commands)
            assert config.read_bytes() == desired and last.read_bytes() == previous
            reset()
            config.write_bytes(desired + b'regenerate_on_reload = false\n')
            def fail_check(args: list[str], timeout: float = 20) -> None:
                if "check-filler" in args:
                    raise ReloadError("synthetic_profile_mismatch")
                command(args, timeout)
            with patch.dict(globals(), run_checked=fail_check):
                try:
                    reload_with_feedback((), (), root / "socket")
                except ReloadError:
                    pass
                else:
                    raise AssertionError("mismatched assets activated without generation")
            assert not restarted and old == {name: (filler / name).read_bytes() for name in FILLER_FILES}
            reset()
            for name in FILLER_FILES:
                (filler / name).unlink()
            filler.rmdir()
            filler.parent.rmdir()
            reload_with_feedback((), (), root / "socket")
            assert all((filler / name).is_file() for name in FILLER_FILES)
    print("feedback reload staging/lock/idle/reuse/failure/rollback self-test: ok")


def main() -> int:
    parser = argparse.ArgumentParser(description="Safely reload Kienzlefon AI telephone agents")
    parser.add_argument("--check", action="store_true", help="validate without changing services")
    parser.add_argument("--self-test", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.self_test:
        feedback_reload_self_test()
        return 0
    if os.geteuid() != 0:
        raise ReloadError("root_required")
    slot_ids, agent_sockets, capacity_socket = validate_configuration()
    if args.check:
        run_checked([sys.executable, str(AGENT), "check-filler", "--config", str(CONFIG)])
        inspect(agent_sockets, capacity_socket)
    else:
        reload_with_feedback(slot_ids, agent_sockets, capacity_socket)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        code = str(error) if isinstance(error, ReloadError) else type(error).__name__
        print(f"RELOAD_FAIL code={code}", file=sys.stderr)
        raise SystemExit(1)
PY
  chmod 0755 "$temp"
  mv -f "$temp" "$target"
}

write_debug_console() {
  local target="$1"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<'PY'
#!/usr/bin/env python3
"""Local, non-persistent live console for the Kienzlefon AI backend."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import socket
import sys
import time
import tomllib
from datetime import datetime
from pathlib import Path
from typing import Any, Mapping

VERSION = "2.5.1"
CONFIG = Path("/etc/kienzlefon-ai-asterisk-backend/backend.toml")
DEBUG_PROTOCOL = "kienzlefon-ai-debug-v1"
CONTROL_PROTOCOL = "kienzlefon-ai-capacity-control-v1"
SENSITIVE_KEYS = {
    "text", "reply", "transcript", "prompt", "messages", "fields",
    "raw_response", "normalized_response",
}
FORBIDDEN_KEYS = {"caller_id", "request_id", "lease_id", "call_uuid"}
MAX_EVENT_BYTES = 2 * 1024 * 1024


class ConsoleError(RuntimeError):
    pass


def load_configuration(path: Path = CONFIG) -> dict[str, Any]:
    with path.open("rb") as handle:
        raw = tomllib.load(handle)
    backend = raw["backend"]
    sip = raw["sip"]
    admission = raw["admission"]
    debug = raw.get("debug", {})
    slot_ids = tuple(str(value) for value in sip["slot_ids"])
    if slot_ids != ("ai-slot-00", "ai-slot-01", "ai-slot-02"):
        raise ConsoleError("slot_configuration_invalid")
    runtime = Path(str(backend["runtime_directory"]))
    capacity_socket = Path(str(admission["control_socket"]))
    allow_sensitive = debug.get("allow_sensitive_console", False)
    interval_ms = debug.get("metrics_interval_ms", 250)
    if not runtime.is_absolute() or not capacity_socket.is_absolute():
        raise ConsoleError("control_path_invalid")
    if not isinstance(allow_sensitive, bool):
        raise ConsoleError("sensitive_console_switch_invalid")
    if isinstance(interval_ms, bool) or not isinstance(interval_ms, int):
        raise ConsoleError("metrics_interval_invalid")
    if not 100 <= interval_ms <= 5000:
        raise ConsoleError("metrics_interval_invalid")
    return {
        "slot_ids": slot_ids,
        "agent_sockets": tuple(runtime / f"slot-{index}" / "control.sock" for index in range(3)),
        "text_socket": runtime / "text" / "control.sock",
        "capacity_socket": capacity_socket,
        "allow_sensitive": allow_sensitive,
        "interval_ms": interval_ms,
    }


def unix_request(path: Path, message: Mapping[str, Any]) -> Mapping[str, Any]:
    body = json.dumps(message, separators=(",", ":")).encode() + b"\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(3.0)
        client.connect(str(path))
        client.sendall(body)
        response = bytearray()
        while not response.endswith(b"\n"):
            if len(response) > MAX_EVENT_BYTES:
                raise ConsoleError("control_response_too_large")
            block = client.recv(4096)
            if not block:
                raise ConsoleError("control_response_closed")
            response.extend(block)
    value = json.loads(response)
    if not isinstance(value, Mapping):
        raise ConsoleError("control_response_invalid")
    return value


def local_event(event: str, source: str, **values: Any) -> dict[str, Any]:
    return {
        "protocol": DEBUG_PROTOCOL,
        "epoch_ms": time.time_ns() // 1_000_000,
        "monotonic_ms": time.monotonic_ns() // 1_000_000,
        "slot_id": source,
        "event": event,
        **values,
    }


def sanitize_event(value: Mapping[str, Any], show_text: bool) -> dict[str, Any]:
    result = {str(key): item for key, item in value.items()}
    for key in FORBIDDEN_KEYS:
        result.pop(key, None)
    if not show_text:
        for key in SENSITIVE_KEYS:
            result.pop(key, None)
        result.pop("sensitive", None)
    return result


def publisher_event(response: Mapping[str, Any]) -> dict[str, Any]:
    if response.get("protocol") != CONTROL_PROTOCOL or response.get("accepted") is not True:
        raise ConsoleError("publisher_status_invalid")
    raw_slots = response.get("slots")
    if not isinstance(raw_slots, Mapping):
        raise ConsoleError("publisher_slots_invalid")
    slots: dict[str, str] = {}
    reasons: dict[str, str] = {}
    for slot_id in ("ai-slot-00", "ai-slot-01", "ai-slot-02"):
        item = raw_slots.get(slot_id)
        if not isinstance(item, Mapping):
            raise ConsoleError("publisher_slots_incomplete")
        slots[slot_id] = str(item.get("state", "unknown"))
        reasons[slot_id] = str(item.get("reason", "unknown"))
    return local_event(
        "publisher_status",
        "publisher",
        listener_connected=response.get("listener_connected") is True,
        last_snapshot_accepted=response.get("last_snapshot_accepted") is True,
        free_slots=int(response.get("free_slots", 0)),
        service_capacity=int(response.get("service_capacity", 0)),
        service_reason=str(response.get("service_reason", "unknown")),
        slots=slots,
        slot_reasons=reasons,
    )


def print_event(value: Mapping[str, Any], json_mode: bool, show_text: bool) -> None:
    event = sanitize_event(value, show_text)
    if json_mode:
        print(json.dumps(event, ensure_ascii=False, separators=(",", ":")), flush=True)
        return
    epoch_ms = event.get("epoch_ms")
    if isinstance(epoch_ms, int):
        timestamp = datetime.fromtimestamp(epoch_ms / 1000).astimezone().isoformat(timespec="milliseconds")
    else:
        timestamp = datetime.now().astimezone().isoformat(timespec="milliseconds")
    slot_id = str(event.get("slot_id", "console"))
    event_name = str(event.get("event", "unknown"))
    omitted = {"protocol", "epoch_ms", "monotonic_ms", "sequence", "slot_id", "event"}
    details = " ".join(
        f"{key}={json.dumps(item, ensure_ascii=False, separators=(',', ':'))}"
        for key, item in event.items()
        if key not in omitted
    )
    print(f"[{timestamp}] {slot_id} {event_name}" + (f" {details}" if details else ""), flush=True)


async def subscribe_slot(
    slot_index: int,
    path: Path,
    show_text: bool,
    json_mode: bool,
) -> None:
    connected = False
    was_available: bool | None = None
    while True:
        writer: asyncio.StreamWriter | None = None
        try:
            reader, writer = await asyncio.open_unix_connection(str(path), limit=MAX_EVENT_BYTES)
            request = {"command": "debug_subscribe", "show_text": show_text}
            writer.write(json.dumps(request, separators=(",", ":")).encode() + b"\n")
            await writer.drain()
            raw = await asyncio.wait_for(reader.readline(), timeout=3.0)
            acknowledgement = json.loads(raw)
            if (
                not isinstance(acknowledgement, Mapping)
                or acknowledgement.get("ok") is not True
                or acknowledgement.get("protocol") != DEBUG_PROTOCOL
            ):
                raise ConsoleError("debug_subscription_rejected")
            if show_text and acknowledgement.get("show_text") is not True:
                raise ConsoleError("sensitive_subscription_rejected")
            connected = True
            was_available = True
            print_event(
                local_event("console_connected", f"ai-slot-{slot_index:02d}", show_text=show_text),
                json_mode,
                show_text,
            )
            while True:
                raw = await reader.readline()
                if not raw:
                    raise ConsoleError("debug_stream_closed")
                if len(raw) > MAX_EVENT_BYTES:
                    raise ConsoleError("debug_event_too_large")
                event = json.loads(raw)
                if not isinstance(event, Mapping) or event.get("protocol") != DEBUG_PROTOCOL:
                    raise ConsoleError("debug_event_invalid")
                print_event(event, json_mode, show_text)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            code = str(error) if isinstance(error, ConsoleError) else type(error).__name__
            if was_available is not False:
                print_event(
                    local_event(
                        "console_disconnected" if connected else "console_unavailable",
                        f"ai-slot-{slot_index:02d}",
                        code=code,
                    ),
                    json_mode,
                    show_text,
                )
            connected = False
            was_available = False
            await asyncio.sleep(1.0)
        finally:
            if writer is not None:
                writer.close()
                try:
                    await writer.wait_closed()
                except Exception:
                    pass


async def subscribe_text(
    path: Path,
    show_text: bool,
    json_mode: bool,
) -> None:
    connected = False
    was_available: bool | None = None
    while True:
        writer: asyncio.StreamWriter | None = None
        try:
            reader, writer = await asyncio.open_unix_connection(
                str(path), limit=MAX_EVENT_BYTES
            )
            request = {"command": "debug_subscribe", "show_text": show_text}
            writer.write(
                json.dumps(request, separators=(",", ":")).encode() + b"\n"
            )
            await writer.drain()
            raw = await asyncio.wait_for(reader.readline(), timeout=3.0)
            acknowledgement = json.loads(raw)
            if (
                not isinstance(acknowledgement, Mapping)
                or acknowledgement.get("ok") is not True
                or acknowledgement.get("protocol") != DEBUG_PROTOCOL
                or acknowledgement.get("source") != "chat"
            ):
                raise ConsoleError("chat_debug_subscription_rejected")
            if show_text and acknowledgement.get("show_text") is not True:
                raise ConsoleError("chat_sensitive_subscription_rejected")
            connected = True
            was_available = True
            print_event(
                local_event("console_connected", "chat", show_text=show_text),
                json_mode,
                show_text,
            )
            while True:
                raw = await reader.readline()
                if not raw:
                    raise ConsoleError("chat_debug_stream_closed")
                if len(raw) > MAX_EVENT_BYTES:
                    raise ConsoleError("chat_debug_event_too_large")
                event = json.loads(raw)
                if (
                    not isinstance(event, Mapping)
                    or event.get("protocol") != DEBUG_PROTOCOL
                    or event.get("slot_id") != "chat"
                ):
                    raise ConsoleError("chat_debug_event_invalid")
                print_event(event, json_mode, show_text)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            code = str(error) if isinstance(error, ConsoleError) else type(error).__name__
            if was_available is not False:
                print_event(
                    local_event(
                        "console_disconnected" if connected else "console_unavailable",
                        "chat",
                        code=code,
                    ),
                    json_mode,
                    show_text,
                )
            connected = False
            was_available = False
            await asyncio.sleep(1.0)
        finally:
            if writer is not None:
                writer.close()
                try:
                    await writer.wait_closed()
                except Exception:
                    pass


async def poll_publisher(path: Path, json_mode: bool, show_text: bool) -> None:
    previous = ""
    was_available: bool | None = None
    while True:
        try:
            response = await asyncio.to_thread(
                unix_request,
                path,
                {"protocol": CONTROL_PROTOCOL, "command": "status"},
            )
            event = publisher_event(response)
            # Ignore timestamps when deciding whether the technical state changed.
            fingerprint = json.dumps(
                {key: value for key, value in event.items() if key not in {"epoch_ms", "monotonic_ms"}},
                sort_keys=True,
                separators=(",", ":"),
            )
            if fingerprint != previous or was_available is not True:
                print_event(event, json_mode, show_text)
            previous = fingerprint
            was_available = True
        except asyncio.CancelledError:
            raise
        except Exception as error:
            if was_available is not False:
                code = str(error) if isinstance(error, ConsoleError) else type(error).__name__
                print_event(
                    local_event("publisher_unavailable", "publisher", code=code),
                    json_mode,
                    show_text,
                )
            was_available = False
        await asyncio.sleep(1.0)


def snapshot(config: Mapping[str, Any], slots: tuple[int, ...], json_mode: bool) -> int:
    failed = False
    for index in slots:
        try:
            response = unix_request(config["agent_sockets"][index], {"command": "status"})
            if response.get("ok") is not True:
                raise ConsoleError("agent_status_rejected")
            event = local_event(
                "slot_status",
                str(response.get("slot_id", f"ai-slot-{index:02d}")),
                state=str(response.get("state", "unknown")),
                sip_registered=response.get("sip_registered") is True,
                publisher_reachable=response.get("publisher_reachable") is True,
                audiosocket_format=str(response.get("audiosocket_format", "unknown")),
                audiosocket_type=str(response.get("audiosocket_type", "unknown")),
                audiosocket_sample_rate=int(response.get("audiosocket_sample_rate", 0)),
                frame_ms=int(response.get("frame_ms", 0)),
                frame_bytes=int(response.get("frame_bytes", 0)),
            )
        except Exception as error:
            failed = True
            event = local_event(
                "slot_unavailable",
                f"ai-slot-{index:02d}",
                code=str(error) if isinstance(error, ConsoleError) else type(error).__name__,
            )
        print_event(event, json_mode, False)
    try:
        response = unix_request(
            config["capacity_socket"],
            {"protocol": CONTROL_PROTOCOL, "command": "status"},
        )
        event = publisher_event(response)
    except Exception as error:
        failed = True
        event = local_event(
            "publisher_unavailable",
            "publisher",
            code=str(error) if isinstance(error, ConsoleError) else type(error).__name__,
        )
    print_event(event, json_mode, False)
    return 1 if failed else 0


async def follow(
    config: Mapping[str, Any], slots: tuple[int, ...], show_text: bool, json_mode: bool
) -> None:
    tasks = [
        asyncio.create_task(
            subscribe_slot(index, config["agent_sockets"][index], show_text, json_mode)
        )
        for index in slots
    ]
    tasks.append(
        asyncio.create_task(
            subscribe_text(config["text_socket"], show_text, json_mode)
        )
    )
    tasks.append(asyncio.create_task(poll_publisher(config["capacity_socket"], json_mode, show_text)))
    await asyncio.gather(*tasks)


def self_test() -> int:
    public = sanitize_event(
        {"protocol": DEBUG_PROTOCOL, "event": "asr_partial", "chars": 12, "text": "privat", "request_id": "secret"},
        False,
    )
    assert public == {"protocol": DEBUG_PROTOCOL, "event": "asr_partial", "chars": 12}
    sensitive = sanitize_event(
        {"protocol": DEBUG_PROTOCOL, "event": "asr_partial", "text": "sichtbar", "caller_id": "secret"},
        True,
    )
    assert sensitive.get("text") == "sichtbar" and "caller_id" not in sensitive
    print("debug console self-test: ok")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Live-Diagnose der drei Kienzlefon-AI-Telefonagenten"
    )
    parser.add_argument("--slot", type=int, choices=(0, 1, 2), help="nur einen Slot anzeigen")
    parser.add_argument("--json", action="store_true", help="JSONL statt lesbarer Zeilen")
    parser.add_argument("--snapshot", action="store_true", help="Status einmalig anzeigen")
    parser.add_argument("--show-text", action="store_true", help="explizit freigegebene Gesprächsinhalte live anzeigen")
    parser.add_argument("--self-test", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if os.geteuid() != 0:
        raise ConsoleError("root_required")
    config = load_configuration()
    if args.show_text and not config["allow_sensitive"]:
        raise ConsoleError("sensitive_console_not_enabled_in_toml")
    slots = (args.slot,) if args.slot is not None else (0, 1, 2)
    if args.snapshot:
        return snapshot(config, slots, args.json)
    if args.show_text:
        print(
            "WARNING: Sensitive ASR/LLM/TTS text is visible in this terminal only; "
            "do not redirect or record the output.",
            file=sys.stderr,
            flush=True,
        )
    asyncio.run(follow(config, slots, args.show_text, args.json))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as error:
        print(f"DEBUG_CONSOLE_FAIL code={str(error) or type(error).__name__}", file=sys.stderr)
        raise SystemExit(1)
PY
  chmod 0755 "$temp"
  mv -f "$temp" "$target"
}

write_performance_report() {
  local target="$1"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<'PY'
#!/usr/bin/env python3
"""Aggregate privacy-safe Kienzlefon performance JSONL by runtime version."""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable, Mapping

VERSION = "2.5.1"
SCHEMA = "kienzlefon-performance-v1"
DEFAULT_LOG = Path("/var/log/kienzlefon-ai-asterisk-backend/performance.jsonl")
METRICS = (
    "beep_count",
    "beep_audio_ms",
    "end_of_detected_speech_to_first_beep_audio_ms",
    "end_of_actual_speech_to_first_beep_audio_ms",
    "filler_available",
    "filler_blocks_started",
    "filler_blocks_completed",
    "filler_audio_ms",
    "end_of_detected_speech_to_first_filler_audio_ms",
    "end_of_actual_speech_to_first_filler_audio_ms",
    "reply_audio_wait_for_filler_ms",
    "speech_duration_ms",
    "endpoint_silence_ms",
    "asr_ms",
    "asr_connect_ms",
    "asr_final_after_speech_end_ms",
    "end_of_detected_speech_to_llm_start_ms",
    "llm_ms",
    "llm_speculative_requests",
    "llm_speculative_discarded",
    "llm_speculative_failures",
    "llm_speculative_reused",
    "llm_speculative_lead_ms",
    "llm_wait_after_asr_final_ms",
    "tts_first_audio_generated_ms",
    "tts_first_audio_written_ms",
    "tts_total_ms",
    "end_of_detected_speech_to_first_reply_audio_ms",
    "end_of_actual_speech_to_first_reply_audio_ms",
    "audio_queue_dropped_frames",
)
FORBIDDEN_KEYS = {
    "audio", "caller_id", "call_uuid", "lease_id", "request_id",
    "text", "transcript", "prompt", "reply", "raw_response",
    "normalized_response", "tts_input", "token",
}


class ReportError(RuntimeError):
    pass


def finite_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def percentile(values: Iterable[float], fraction: float) -> float | None:
    ordered = sorted(values)
    if not ordered:
        return None
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def log_paths(base: Path, backup_limit: int = 20) -> list[Path]:
    candidates = [base]
    candidates.extend(Path(f"{base}.{index}") for index in range(1, backup_limit + 1))
    return [path for path in candidates if path.is_file()]


def load_records(paths: Iterable[Path]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for path in paths:
        with path.open("r", encoding="ascii") as handle:
            for line_number, raw in enumerate(handle, start=1):
                try:
                    value = json.loads(raw)
                except json.JSONDecodeError as exc:
                    raise ReportError(f"invalid_json:{path.name}:{line_number}") from exc
                if not isinstance(value, dict) or value.get("schema") != SCHEMA:
                    raise ReportError(f"invalid_schema:{path.name}:{line_number}")
                if FORBIDDEN_KEYS.intersection(value):
                    raise ReportError(f"forbidden_field:{path.name}:{line_number}")
                version = value.get("program_version")
                mode = value.get("pipeline_mode")
                if not isinstance(version, str) or not re.fullmatch(
                    r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", version
                ):
                    raise ReportError(f"invalid_version:{path.name}:{line_number}")
                if not isinstance(mode, str) or not re.fullmatch(r"[a-z0-9_]+", mode):
                    raise ReportError(f"invalid_mode:{path.name}:{line_number}")
                records.append(value)
    return records


def aggregate(records: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    groups: dict[tuple[str, str], list[Mapping[str, Any]]] = defaultdict(list)
    for record in records:
        groups[(str(record["program_version"]), str(record["pipeline_mode"]))].append(record)
    output: list[dict[str, Any]] = []
    for (version, mode), rows in sorted(
        groups.items(),
        key=lambda item: (
            tuple(int(part) for part in item[0][0].split(".")),
            item[0][1],
        ),
    ):
        completed = sum(row.get("outcome") == "completed" for row in rows)
        cancelled = sum(row.get("outcome") == "caller_hangup" for row in rows)
        failed = len(rows) - completed - cancelled
        summaries: dict[str, Any] = {}
        for metric in METRICS:
            values = [
                number
                for row in rows
                if (number := finite_number(row.get(metric))) is not None
            ]
            summaries[metric] = {
                "count": len(values),
                "median": statistics.median(values) if values else None,
                "p95": percentile(values, 0.95),
                "max": max(values) if values else None,
            }
        output.append({
            "program_version": version,
            "pipeline_mode": mode,
            "records": len(rows),
            "completed": completed,
            "failed": failed,
            "cancelled": cancelled,
            "error_rate": failed / (len(rows) - cancelled) if len(rows) > cancelled else 0.0,
            "metrics": summaries,
        })
    return {"schema": "kienzlefon-performance-report-v1", "groups": output}


def print_human(report: Mapping[str, Any]) -> None:
    groups = report.get("groups", [])
    if not groups:
        print("Keine Performance-Datensätze gefunden.")
        return
    for group in groups:
        print(
            f"Version {group['program_version']} / {group['pipeline_mode']}: "
            f"{group['records']} Turns, {group['failed']} Fehler, "
            f"Fehlerrate {group['error_rate'] * 100:.1f}%"
        )
        if group["cancelled"]:
            print(f"  Durch Auflegen abgebrochen: {group['cancelled']} (keine technischen Fehler)")
        for metric in METRICS:
            values = group["metrics"][metric]
            if values["count"]:
                print(
                    f"  {metric}: n={values['count']} "
                    f"Median={values['median']:.1f} P95={values['p95']:.1f} "
                    f"Max={values['max']:.1f}"
                )


def self_test() -> int:
    fixture = []
    for version, values in (("2.1.3", (1000, 1200, 1400)), ("2.2", (700, 800, 900))):
        for index, latency in enumerate(values, start=1):
            fixture.append({
                "program_version": version,
                "pipeline_mode": "half_duplex" if version == "2.1.3" else "streaming_asr",
                "outcome": "completed",
                "end_of_actual_speech_to_first_reply_audio_ms": latency,
                "audio_queue_dropped_frames": index - 1,
            })
    report = aggregate(fixture)
    assert len(report["groups"]) == 2
    assert report["groups"][0]["metrics"][
        "end_of_actual_speech_to_first_reply_audio_ms"
    ]["median"] == 1200
    assert report["groups"][1]["metrics"][
        "end_of_actual_speech_to_first_reply_audio_ms"
    ]["p95"] == 890
    assert report["groups"][0]["metrics"]["asr_final_after_speech_end_ms"]["count"] == 0
    mixed = aggregate(fixture + [{
        "program_version": "2.5.1", "pipeline_mode": "half_duplex",
        "outcome": "completed", "asr_final_after_speech_end_ms": 1234,
    }])
    assert len(mixed["groups"]) == 3
    speculative_report = aggregate(fixture + [{
        "program_version": "2.3", "pipeline_mode": "streaming_asr_speculative_llm",
        "outcome": "completed", "llm_speculative_requests": 2,
        "llm_speculative_discarded": 1, "llm_speculative_reused": 1,
        "llm_speculative_lead_ms": 900, "llm_wait_after_asr_final_ms": 50,
        "end_of_detected_speech_to_llm_start_ms": -400,
    }, {
        "program_version": "2.3", "pipeline_mode": "streaming_asr",
        "outcome": "completed", "llm_speculative_requests": 0,
    }])
    assert len(speculative_report["groups"]) == 4
    last = speculative_report["groups"][-1]["metrics"]
    assert last["end_of_detected_speech_to_llm_start_ms"]["median"] == -400
    assert last["llm_speculative_reused"]["median"] == 1
    assert speculative_report["groups"][0]["metrics"]["llm_speculative_requests"]["count"] == 0
    filler_report = aggregate(fixture + [
        {"program_version": "2.5.1", "pipeline_mode": mode, "outcome": "completed",
         "end_of_actual_speech_to_first_filler_audio_ms": first,
         "end_of_actual_speech_to_first_reply_audio_ms": reply,
         "reply_audio_wait_for_filler_ms": wait, "filler_blocks_started": count}
        for mode, first, reply, wait, count in (
            ("half_duplex_filler", 510, 5100, 90, 2),
            ("half_duplex_filler", 520, 5300, 110, 3),
            ("half_duplex", None, 5000, None, 0))
    ])
    assert len(filler_report["groups"]) == 4
    latest = filler_report["groups"][-1]["metrics"]
    assert latest["end_of_actual_speech_to_first_filler_audio_ms"]["median"] == 515
    assert latest["end_of_actual_speech_to_first_reply_audio_ms"]["median"] == 5200
    assert latest["reply_audio_wait_for_filler_ms"]["median"] == 100
    assert filler_report["groups"][0]["metrics"]["filler_blocks_started"]["count"] == 0
    cancelled_report = aggregate([
        {"program_version": "2.5.1", "pipeline_mode": "streaming_asr", "outcome": outcome}
        for outcome in ("completed", "failed", "caller_hangup")
    ])["groups"][0]
    assert cancelled_report["cancelled"] == 1
    assert cancelled_report["failed"] == 1 and cancelled_report["error_rate"] == 0.5
    only_hangup = aggregate([{
        "program_version": "2.5.1", "pipeline_mode": "streaming_asr", "outcome": "caller_hangup"
    }])["groups"][0]
    assert only_hangup["failed"] == 0 and only_hangup["error_rate"] == 0.0
    with tempfile.TemporaryDirectory(prefix="kzf-performance-report-") as directory:
        path = Path(directory) / "performance.jsonl"
        path.write_text(
            json.dumps({
                "schema": SCHEMA,
                "program_version": "2.5.1",
                "pipeline_mode": "half_duplex",
                "outcome": "completed",
            }) + "\n",
            encoding="ascii",
        )
        loaded = load_records([path])
        assert len(loaded) == 1
        assert loaded[0]["program_version"] == "2.5.1"
    print("performance report self-test: ok")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Kienzlefon-Performance nach Programmversion vergleichen"
    )
    parser.add_argument("--log-file", type=Path, default=DEFAULT_LOG)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--self-test", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    report = aggregate(load_records(log_paths(args.log_file)))
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print_human(report)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ReportError as error:
        print(f"PERFORMANCE_REPORT_FAIL code={error}")
        raise SystemExit(1)
PY
  chmod 0755 "$temp"
  mv -f "$temp" "$target"
}

write_agent() {
  local target="$1"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<'PY'
#!/usr/bin/env python3
"""Kienzlefon AI telephone agent runtime v2.5.1.

Normal logs contain technical state only.  Caller IDs, transcripts, prompts,
LLM content, field values and TTS input are never logged.
"""

from __future__ import annotations

import argparse
import array
import asyncio
import base64
import contextlib
import copy
import fcntl
import hashlib
import http.client
import json
import logging
import math
import os
import queue
import re
import signal
import socket
import socketserver
import ssl
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
import uuid
from collections import deque
from dataclasses import dataclass, field, replace
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping
from urllib.parse import urlsplit

VERSION = "2.5.1"
PROTOCOL = "kienzlefon-ai-admission-v1"
CONTROL_PROTOCOL = "kienzlefon-ai-capacity-control-v1"
DEBUG_PROTOCOL = "kienzlefon-ai-debug-v1"
AUDIO_TYPE_SLIN16 = 0x12
UUID_TYPE = 0x01
DTMF_TYPE = 0x03
TERMINATE_TYPE = 0x00
ERROR_TYPE = 0xFF
FRAME_MS = 20
PCM_WIDTH = 2
TELEPHONY_RATE = 16000
ASR_RATE = 16000
TELEPHONY_FORMAT = "slin16"
TELEPHONY_FRAME_BYTES = TELEPHONY_RATE * PCM_WIDTH * FRAME_MS // 1000
PERFORMANCE_SCHEMA = "kienzlefon-performance-v1"
MANAGED_PERFORMANCE_LOG = Path(
    "/var/log/kienzlefon-ai-asterisk-backend/performance.jsonl"
)
MAX_DEBUG_SUBSCRIBERS = 8
MAX_TEXT_DEBUG_SUBSCRIBERS = 8
IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")
LEASE_RE = re.compile(r"^[A-Za-z0-9._:-]{16,128}$")
PHONE_RE = re.compile(r"^[+0-9*#A-Da-d._ -]{0,64}$")
ALLOWED_CALL_TYPES = {
    "rezeptbestellung": ("vorname", "nachname", "geburtsdatum", "medikamente"),
    "ueb_req": ("vorname", "nachname", "geburtsdatum", "fachrichtung", "grund"),
    "termin": ("vorname", "nachname", "geburtsdatum", "grund"),
    "rueckruf_details": ("vorname", "nachname", "geburtsdatum"),
    "rueckruf_tel_grund": ("telefon",),
    "sonstiges": ("anliegen",),
}
ALLOWED_ACTIONS = (
    "none", "warteschlange", "priorisierung", "rotes_telefon", "beenden"
)
ACTION_TARGETS = {
    "warteschlange": "practice_queue",
    "priorisierung": "pharmacy_queue",
    "rotes_telefon": "super_priority",
}
ACTION_POLICY_FIELDS = {
    "warteschlange": "practice_queue_allowed",
    "priorisierung": "pharmacy_transfer_allowed",
    "rotes_telefon": "specialist_transfer_allowed",
}
ALLOWED_CHANNELS = ("telephone", "chat")
ALLOWED_CALLER_ROLES = ("patient", "care_service", "professional_urgent", "other", "unknown")
ALLOWED_URGENCIES = ("normal", "emergency")

FINAL_CHECK_QUESTION = "Haben Sie noch ein Anliegen?"
FINAL_FAREWELL = "Vielen Dank. Tschüss."

ALL_FIELDS = (
    "vorname",
    "nachname",
    "geburtsdatum",
    "telefon",
    "medikamente",
    "fachrichtung",
    "grund",
    "anliegen",
)
FIELD_LIMIT = 2000
from kienzlefon_tts_guard import normalize_tts_text

REPLY_LIMIT = 1000
SUMMARY_LIMIT = 8000
TRANSCRIPT_LIMIT = 12000
MAX_TEXT_REQUEST_BYTES = 65536
MAX_TEXT_SESSIONS = 64
MAX_CONTROL_RESPONSE_BYTES = 65536
LOGGER = logging.getLogger("kienzlefon-ai-agent")
SENSITIVE_DEBUG_KEYS = {
    "text", "transcript", "reply", "prompt", "messages", "fields",
    "caller_id", "request_id", "lease_id", "call_uuid",
}
DebugCallback = Callable[
    [str, Mapping[str, Any], Mapping[str, Any] | None], None
]


class AgentError(RuntimeError):
    pass


class ProtocolError(AgentError):
    pass


class CallerHangup(AgentError):
    pass


def diagnostic_error_code(error: BaseException) -> str:
    if isinstance(error, AgentError):
        code = str(error)
        if IDENTIFIER_RE.fullmatch(code):
            return code
    return type(error).__name__


def debug_notify(
    callback: DebugCallback | None,
    event: str,
    values: Mapping[str, Any] | None = None,
    sensitive: Mapping[str, Any] | None = None,
) -> None:
    if callback is not None:
        try:
            callback(event, values or {}, sensitive)
        except Exception:
            # Diagnostics are strictly fail-open for the telephone pipeline.
            return


@dataclass(frozen=True)
class AgentConfig:
    source: Path
    slot_count: int
    first_audio_port: int
    runtime_directory: Path
    state_directory: Path
    kienzlefon_config: Path
    kienzlefon_python: Path
    slot_ids: tuple[str, ...]
    extensions: tuple[str, ...]
    asr_url: str
    llm_url: str
    qwen_url: str
    piper_url: str
    http_timeout: float
    asr_timeout: float
    tts_backend: str
    qwen_speaker: str
    qwen_language: str
    qwen_seed: int
    max_turns: int
    max_llm_tokens: int
    temperature: float
    system_prompt: str
    telephone_overlay: str
    chat_overlay: str
    greeting: str
    technical_failure: str
    completion: str
    energy_threshold: int
    preroll_ms: int
    speech_start_ms: int
    speech_end_ms: int
    minimum_utterance_ms: int
    maximum_utterance_ms: int
    debug_allow_sensitive_console: bool
    debug_metrics_interval_ms: int
    performance_enabled: bool
    performance_log_file: Path
    performance_max_bytes: int
    performance_backup_count: int
    admission_enabled: bool
    capacity_control_socket: Path
    text_api_enabled: bool
    text_api_bind: str
    text_api_port: int
    streaming_asr: bool = False
    speculative_llm: bool = False
    filler_enabled: bool = False
    filler_seed: int = 12345
    filler_texts: tuple[str, ...] = ("Bitte warten.", "Ich verarbeite.", "Bitte warten.")
    filler_start_ms: tuple[int, ...] = (2000, 7000, 13000)
    filler_regenerate_on_reload: bool = True
    filler_beep_enabled: bool = True
    filler_beep_start_ms: int = 0
    filler_beep_interval_ms: int = 1000
    filler_beep_frequency_hz: int = 400
    filler_beep_duration_ms: int = 100
    filler_beep_volume: float = 0.15

    def slot_id(self, index: int) -> str:
        return self.slot_ids[index]

    def extension(self, index: int) -> str:
        return self.extensions[index]

    def audio_port(self, index: int) -> int:
        return self.first_audio_port + index

    def control_socket(self, index: int) -> Path:
        return self.runtime_directory / f"slot-{index}" / "control.sock"


@dataclass
class Claim:
    call_uuid: str
    request_id: str
    lease_id: str
    caller_id: str
    native_format: str
    read_format: str
    write_format: str
    expires_at: float


@dataclass
class DebugSubscriber:
    queue: asyncio.Queue[dict[str, Any]]
    show_text: bool
    dropped: int = 0


@dataclass
class OrderState:
    order_id: str
    call_type: str
    fields: dict[str, str]
    zusammenfassung: str
    complete: bool
    committed: bool = False
    call_id: str = ""


@dataclass
class ConversationState:
    channel: str
    caller_id: str = ""
    final_check: bool = False
    final_check_order_ids: tuple[str, ...] = ()
    pending_au: str = ""
    au_callback_pending: bool = False
    au_handled: bool = False
    orders: list[OrderState] = field(default_factory=list)
    action: str = "none"
    messages: list[dict[str, str]] = field(default_factory=list)
    next_order_number: int = 1


@dataclass
class LLMResult:
    reply: str
    action: str
    orders: list[OrderState]
    raw: dict[str, Any]
    repairs: tuple[str, ...] = ()


@dataclass(frozen=True)
class UtteranceResult:
    pcm: bytes
    speech_duration_ms: int
    utterance_ms: int
    endpoint_silence_ms: int
    endpoint_reason: str
    endpoint_detected_monotonic_ns: int
    actual_speech_end_monotonic_ns: int


@dataclass(frozen=True)
class ASRResult:
    transcript: str
    duration_ms: int
    connect_ms: int
    partial_count: int
    confirmed_count: int


@dataclass(frozen=True)
class TTSMetrics:
    backend: str
    first_audio_generated_ms: int | None
    first_audio_written_ms: int | None
    first_audio_written_monotonic_ns: int | None
    duration_ms: int
    audio_ms: int


@dataclass
class TurnPerformance:
    turn: int
    utterance: UtteranceResult
    audio_queue_dropped_frames: int = 0
    asr_ms: int | None = None
    asr_connect_ms: int | None = None
    asr_final_after_speech_end_ms: int | None = None
    end_of_detected_speech_to_llm_start_ms: int | None = None
    asr_partial_count: int | None = None
    asr_confirmed_count: int | None = None
    transcript_chars: int | None = None
    llm_ms: int | None = None
    llm_speculative_requests: int = 0
    llm_speculative_discarded: int = 0
    llm_speculative_failures: int = 0
    llm_speculative_reused: int = 0
    llm_speculative_lead_ms: int | None = None
    llm_wait_after_asr_final_ms: int | None = None
    reply_chars: int | None = None
    tts_backend: str | None = None
    tts_first_audio_generated_ms: int | None = None
    tts_first_audio_written_ms: int | None = None
    tts_total_ms: int | None = None
    tts_audio_ms: int | None = None
    end_of_detected_speech_to_first_reply_audio_ms: int | None = None
    end_of_actual_speech_to_first_reply_audio_ms: int | None = None
    filler_available: int = 0
    filler_blocks_started: int = 0
    filler_blocks_completed: int = 0
    filler_audio_ms: int = 0
    beep_count: int = 0
    beep_audio_ms: int = 0
    end_of_detected_speech_to_first_beep_audio_ms: int | None = None
    end_of_actual_speech_to_first_beep_audio_ms: int | None = None
    end_of_detected_speech_to_first_filler_audio_ms: int | None = None
    end_of_actual_speech_to_first_filler_audio_ms: int | None = None
    reply_audio_wait_for_filler_ms: int | None = None


@dataclass
class AudioInputStats:
    queue_dropped_frames: int = 0


def apply_tts_performance(
    turn: TurnPerformance,
    tts: TTSMetrics,
    reply_chars: int,
) -> None:
    turn.reply_chars = reply_chars
    turn.tts_backend = tts.backend
    turn.tts_first_audio_generated_ms = tts.first_audio_generated_ms
    turn.tts_first_audio_written_ms = tts.first_audio_written_ms
    turn.tts_total_ms = tts.duration_ms
    turn.tts_audio_ms = tts.audio_ms
    if tts.first_audio_written_monotonic_ns is not None:
        turn.end_of_detected_speech_to_first_reply_audio_ms = round(
            (
                tts.first_audio_written_monotonic_ns
                - turn.utterance.endpoint_detected_monotonic_ns
            ) / 1_000_000
        )
        turn.end_of_actual_speech_to_first_reply_audio_ms = round(
            (
                tts.first_audio_written_monotonic_ns
                - turn.utterance.actual_speech_end_monotonic_ns
            ) / 1_000_000
        )


PERFORMANCE_RECORD_KEYS = frozenset({
    "beep_count",
    "beep_audio_ms",
    "end_of_detected_speech_to_first_beep_audio_ms",
    "end_of_actual_speech_to_first_beep_audio_ms",
    "filler_available",
    "filler_blocks_started",
    "filler_blocks_completed",
    "filler_audio_ms",
    "end_of_detected_speech_to_first_filler_audio_ms",
    "end_of_actual_speech_to_first_filler_audio_ms",
    "reply_audio_wait_for_filler_ms",
    "schema",
    "schema_version",
    "program_version",
    "recorded_at",
    "epoch_ms",
    "slot_id",
    "call_sequence",
    "turn",
    "channel",
    "pipeline_mode",
    "outcome",
    "failure_stage",
    "error_code",
    "vad_energy_threshold",
    "vad_preroll_ms",
    "vad_speech_start_ms",
    "vad_speech_end_ms",
    "speech_duration_ms",
    "utterance_ms",
    "endpoint_silence_ms",
    "endpoint_reason",
    "asr_ms",
    "asr_connect_ms",
    "asr_final_after_speech_end_ms",
    "end_of_detected_speech_to_llm_start_ms",
    "asr_partial_count",
    "asr_confirmed_count",
    "transcript_chars",
    "llm_ms",
    "llm_speculative_requests",
    "llm_speculative_discarded",
    "llm_speculative_failures",
    "llm_speculative_reused",
    "llm_speculative_lead_ms",
    "llm_wait_after_asr_final_ms",
    "reply_chars",
    "tts_backend",
    "tts_first_audio_generated_ms",
    "tts_first_audio_written_ms",
    "tts_total_ms",
    "tts_audio_ms",
    "end_of_detected_speech_to_first_reply_audio_ms",
    "end_of_actual_speech_to_first_reply_audio_ms",
    "audio_queue_dropped_frames",
})


class PerformanceWriter:
    """Bounded asynchronous JSONL writer for content-free turn metrics."""

    def __init__(
        self,
        enabled: bool,
        path: Path,
        max_bytes: int,
        backup_count: int,
    ) -> None:
        self.enabled = enabled
        self.path = path
        self.max_bytes = max_bytes
        self.backup_count = backup_count
        self.records: queue.Queue[dict[str, Any] | None] = queue.Queue(maxsize=256)
        self.dropped = 0
        self.thread: threading.Thread | None = None
        if enabled:
            self.thread = threading.Thread(
                target=self._worker,
                daemon=True,
                name="kienzlefon-performance-writer",
            )
            self.thread.start()

    def submit(self, record: Mapping[str, Any]) -> None:
        if not self.enabled:
            return
        candidate = dict(record)
        if set(candidate) != PERFORMANCE_RECORD_KEYS:
            LOGGER.warning("event=performance_record_rejected code=field_contract")
            return
        try:
            self.records.put_nowait(candidate)
        except queue.Full:
            self.dropped += 1
            LOGGER.warning(
                "event=performance_record_dropped count=%d", self.dropped
            )

    def close(self) -> None:
        if self.thread is None:
            return
        try:
            self.records.put_nowait(None)
        except queue.Full:
            with contextlib.suppress(queue.Empty):
                self.records.get_nowait()
            self.records.put_nowait(None)
        self.thread.join(timeout=5.0)
        if self.thread.is_alive():
            LOGGER.warning("event=performance_writer_stop_timeout")
        self.thread = None

    def _worker(self) -> None:
        while True:
            record = self.records.get()
            if record is None:
                return
            try:
                self._append(record)
            except Exception as error:
                LOGGER.warning(
                    "event=performance_write_failed code=%s",
                    diagnostic_error_code(error),
                )

    def _append(self, record: Mapping[str, Any]) -> None:
        payload = (
            json.dumps(record, ensure_ascii=True, separators=(",", ":")) + "\n"
        ).encode("ascii")
        if len(payload) > 16384:
            raise AgentError("performance_record_too_large")
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
        os.chmod(self.path.parent, 0o750)
        lock_path = self.path.parent / ".performance.lock"
        flags = os.O_WRONLY | os.O_CREAT | os.O_CLOEXEC
        flags |= getattr(os, "O_NOFOLLOW", 0)
        lock_fd = os.open(lock_path, flags, 0o640)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
            if self.path.is_symlink():
                raise AgentError("performance_log_symlink_rejected")
            current_size = self.path.stat().st_size if self.path.exists() else 0
            if current_size and current_size + len(payload) > self.max_bytes:
                self._rotate()
            data_flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_CLOEXEC
            data_flags |= getattr(os, "O_NOFOLLOW", 0)
            data_fd = os.open(self.path, data_flags, 0o640)
            try:
                if not stat.S_ISREG(os.fstat(data_fd).st_mode):
                    raise AgentError("performance_log_not_regular")
                written = os.write(data_fd, payload)
                if written != len(payload):
                    raise AgentError("performance_log_short_write")
                os.fchmod(data_fd, 0o640)
            finally:
                os.close(data_fd)
        finally:
            with contextlib.suppress(OSError):
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)

    def _rotate(self) -> None:
        for index in range(self.backup_count, 1, -1):
            source = Path(f"{self.path}.{index - 1}")
            destination = Path(f"{self.path}.{index}")
            if source.exists():
                if source.is_symlink() or destination.is_symlink():
                    raise AgentError("performance_rotation_symlink_rejected")
                os.replace(source, destination)
        if self.path.exists():
            os.replace(self.path, Path(f"{self.path}.1"))


@dataclass
class ConfirmedSegment:
    start: float | None
    end: float | None
    text: str
    sequence: int


class ConfirmedTranscriptAssembler:
    START_TOLERANCE_SECONDS = 0.08

    def __init__(self) -> None:
        self._segments: list[ConfirmedSegment] = []
        self._sequence = 0

    @staticmethod
    def _time(value: Any) -> float | None:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        result = float(value)
        return result if math.isfinite(result) else None

    @staticmethod
    def _revision(old: str, new: str) -> bool:
        old, new = old.strip(), new.strip()
        return bool(old and new and (old.startswith(new) or new.startswith(old)))

    def add(self, text: str, start: Any, end: Any) -> None:
        text = text.strip()
        if not text:
            return
        start_f, end_f = self._time(start), self._time(end)
        self._sequence += 1
        match: int | None = None
        if start_f is not None:
            match = next(
                (
                    index
                    for index, segment in enumerate(self._segments)
                    if segment.start is not None
                    and abs(segment.start - start_f) <= self.START_TOLERANCE_SECONDS
                ),
                None,
            )
        if match is None and start_f is not None and end_f is not None:
            for index, segment in enumerate(self._segments):
                if (
                    segment.start is not None
                    and segment.end is not None
                    and min(segment.end, end_f)
                    >= max(segment.start, start_f) - self.START_TOLERANCE_SECONDS
                    and self._revision(segment.text, text)
                ):
                    match = index
                    break
        if match is None and start_f is None and self._segments:
            last = self._segments[-1]
            if last.start is None and self._revision(last.text, text):
                match = len(self._segments) - 1
        replacement = ConfirmedSegment(start_f, end_f, text, self._sequence)
        if match is None:
            self._segments.append(replacement)
        else:
            previous = self._segments[match]
            replacement.start = start_f if start_f is not None else previous.start
            replacement.end = end_f if end_f is not None else previous.end
            replacement.sequence = previous.sequence
            self._segments[match] = replacement

    def transcript(self) -> str:
        ordered = sorted(
            self._segments,
            key=lambda item: (1, 0.0, item.sequence)
            if item.start is None
            else (0, item.start, item.sequence),
        )
        return " ".join(item.text for item in ordered).strip()


class EnergyVAD:
    def __init__(self, config: AgentConfig) -> None:
        self.threshold = config.energy_threshold
        self.start_frames = max(1, math.ceil(config.speech_start_ms / FRAME_MS))
        self.end_frames = max(1, math.ceil(config.speech_end_ms / FRAME_MS))
        self.min_frames = max(1, math.ceil(config.minimum_utterance_ms / FRAME_MS))
        self.max_frames = max(1, math.ceil(config.maximum_utterance_ms / FRAME_MS))
        self.preroll: deque[bytes] = deque(
            maxlen=max(1, math.ceil(config.preroll_ms / FRAME_MS))
        )
        self.active = False
        self.speech_run = 0
        self.speech_frames = 0
        self.silence_run = 0
        self.frames: list[bytes] = []
        self.started = False
        self.last_energy = 0
        self.last_peak = 0
        self.last_end_reason = ""
        self.last_frame_count = 0
        self.last_speech_frames = 0
        self.last_silence_frames = 0
        self.last_accepted = False

    @staticmethod
    def levels(frame: bytes) -> tuple[int, int]:
        if not frame:
            return 0, 0
        usable = frame[: len(frame) - len(frame) % 2]
        if not usable:
            return 0, 0
        samples = array.array("h")
        samples.frombytes(usable)
        if sys.byteorder != "little":
            samples.byteswap()
        rms = math.isqrt(sum(int(value) * int(value) for value in samples) // len(samples))
        peak = max(abs(int(value)) for value in samples)
        return rms, peak

    @staticmethod
    def energy(frame: bytes) -> int:
        return EnergyVAD.levels(frame)[0]

    def feed(self, frame: bytes) -> bytes | None:
        self.started = False
        self.last_energy, self.last_peak = self.levels(frame)
        speech = self.last_energy >= self.threshold
        if not self.active:
            self.preroll.append(frame)
            self.speech_run = self.speech_run + 1 if speech else 0
            if self.speech_run >= self.start_frames:
                self.active = True
                self.started = True
                self.frames = list(self.preroll)
                self.preroll.clear()
                self.speech_frames = self.speech_run
                self.silence_run = 0
            return None

        self.frames.append(frame)
        if speech:
            self.speech_frames += 1
        self.silence_run = 0 if speech else self.silence_run + 1
        if len(self.frames) >= self.max_frames or self.silence_run >= self.end_frames:
            result = b"".join(self.frames)
            spoken_frames = self.speech_frames
            self.last_end_reason = (
                "maximum_duration" if len(self.frames) >= self.max_frames else "silence"
            )
            self.last_frame_count = len(self.frames)
            self.last_speech_frames = spoken_frames
            self.last_silence_frames = self.silence_run
            self.last_accepted = spoken_frames >= self.min_frames
            self.reset()
            return result if self.last_accepted else b""
        return None

    def reset(self) -> None:
        self.active = False
        self.speech_run = 0
        self.speech_frames = 0
        self.silence_run = 0
        self.frames = []
        self.preroll.clear()


def load_config(path: str | Path) -> AgentConfig:
    source = Path(path).expanduser().resolve()
    with source.open("rb") as handle:
        raw = tomllib.load(handle)
    backend = raw["backend"]
    sip = raw["sip"]
    services = raw["services"]
    dialog = raw["dialog"]
    vad = raw["vad"]
    debug = raw.get("debug", {})
    performance = raw.get("performance", {})
    admission = raw["admission"]
    text_api = raw.get("text_api", {})
    allow_sensitive_console = debug.get("allow_sensitive_console", False)
    streaming_asr = dialog.get("streaming_asr", False)
    speculative_llm = dialog.get("speculative_llm", False)
    if not isinstance(raw.get("filler", {}), Mapping):
        raise AgentError("invalid_filler_section")
    filler_enabled = raw.get("filler", {}).get("enabled", True)
    filler_seed = raw.get("filler", {}).get("seed", 12345)
    if type(filler_seed) is not int or not 0 <= filler_seed <= 2**31 - 1:
        raise AgentError("invalid_filler_seed")
    if not isinstance(filler_enabled, bool):
        raise AgentError("invalid_filler_switch")
    if not isinstance(speculative_llm, bool):
        raise AgentError("Invalid speculative LLM switch")
    if not isinstance(streaming_asr, bool):
        raise AgentError("Invalid streaming ASR switch")
    if streaming_asr or speculative_llm:
        raise AgentError("version_2_4_requires_block_processing")
    if not isinstance(allow_sensitive_console, bool):
        raise AgentError("Invalid debug sensitive-console switch")
    slot_count = int(backend["slot_count"])
    slot_ids = tuple(str(value) for value in sip["slot_ids"])
    extensions = tuple(str(value) for value in sip["extensions"])
    if slot_count != 3 or len(slot_ids) != 3 or len(extensions) != 3:
        raise AgentError("Version 2.5.1 requires exactly three slots")
    if slot_ids != ("ai-slot-00", "ai-slot-01", "ai-slot-02"):
        raise AgentError("Unexpected slot IDs")
    if extensions != ("8810", "8811", "8812"):
        raise AgentError("Unexpected SIP extensions")
    config = AgentConfig(
        source=source,
        slot_count=slot_count,
        first_audio_port=int(backend["first_audio_port"]),
        runtime_directory=Path(backend["runtime_directory"]),
        state_directory=Path(backend["state_directory"]),
        kienzlefon_config=Path(backend["kienzlefon_config"]),
        kienzlefon_python=Path(backend["kienzlefon_python"]),
        slot_ids=slot_ids,
        extensions=extensions,
        asr_url=str(services["asr_url"]),
        llm_url=str(services["llm_url"]),
        qwen_url=str(services["qwen_url"]),
        piper_url=str(services["piper_url"]),
        http_timeout=float(services["http_timeout_seconds"]),
        asr_timeout=float(services["asr_timeout_seconds"]),
        tts_backend=str(dialog["tts_backend"]),
        qwen_speaker=str(dialog["qwen_speaker"]),
        qwen_language=str(dialog["qwen_language"]),
        qwen_seed=int(dialog["qwen_seed"]),
        max_turns=int(dialog["max_turns"]),
        max_llm_tokens=int(dialog["max_llm_tokens"]),
        temperature=float(dialog["temperature"]),
        system_prompt=_safe_system_prompt(dialog["system_prompt"]),
        telephone_overlay=_safe_system_prompt(dialog["telephone_overlay"]),
        chat_overlay=_safe_system_prompt(dialog["chat_overlay"]),
        greeting=_safe_static_text(dialog["greeting"]),
        technical_failure=_safe_static_text(dialog["technical_failure"]),
        completion=_safe_static_text(dialog["completion"]),
        energy_threshold=int(vad["energy_threshold"]),
        preroll_ms=int(vad["preroll_ms"]),
        speech_start_ms=int(vad["speech_start_ms"]),
        speech_end_ms=int(vad["speech_end_ms"]),
        minimum_utterance_ms=int(vad["minimum_utterance_ms"]),
        maximum_utterance_ms=int(vad["maximum_utterance_ms"]),
        debug_allow_sensitive_console=allow_sensitive_console,
        debug_metrics_interval_ms=int(debug.get("metrics_interval_ms", 250)),
        performance_enabled=bool(performance.get("enabled", False)),
        performance_log_file=Path(str(performance.get(
            "log_file", MANAGED_PERFORMANCE_LOG
        ))),
        performance_max_bytes=int(performance.get("max_bytes", 10485760)),
        performance_backup_count=int(performance.get("backup_count", 5)),
        admission_enabled=bool(admission["enabled"]),
        capacity_control_socket=Path(str(admission["control_socket"])),
        text_api_enabled=bool(text_api.get("enabled", True)),
        text_api_bind=str(text_api.get("bind", "127.0.0.1")),
        text_api_port=int(text_api.get("port", 8300)),
        streaming_asr=streaming_asr,
        speculative_llm=speculative_llm,
        filler_enabled=filler_enabled,
        filler_seed=filler_seed,
        **filler_options(raw.get("filler", {})),
    )
    if not 1024 <= config.first_audio_port <= 65533:
        raise AgentError("Invalid AudioSocket port range")
    if config.tts_backend not in {"qwen", "piper"}:
        raise AgentError("Invalid TTS backend")
    if not 1 <= config.max_turns <= 50:
        raise AgentError("Invalid turn limit")
    if not 100 <= config.energy_threshold <= 10000:
        raise AgentError("Invalid VAD threshold")
    if config.minimum_utterance_ms >= config.maximum_utterance_ms:
        raise AgentError("Invalid utterance duration limits")
    if not 100 <= config.debug_metrics_interval_ms <= 5000:
        raise AgentError("Invalid debug metrics interval")
    if not isinstance(performance.get("enabled", False), bool):
        raise AgentError("Invalid performance logging switch")
    if config.performance_log_file != MANAGED_PERFORMANCE_LOG:
        raise AgentError("Invalid managed performance log path")
    if not 1048576 <= config.performance_max_bytes <= 1073741824:
        raise AgentError("Invalid performance log size")
    if not 1 <= config.performance_backup_count <= 20:
        raise AgentError("Invalid performance backup count")
    if not config.admission_enabled:
        raise AgentError("Admission must be enabled")
    if not config.capacity_control_socket.is_absolute():
        raise AgentError("Invalid capacity control socket")
    if config.text_api_bind != "127.0.0.1":
        raise AgentError("Text API must bind to 127.0.0.1 in version 2.5.1")
    if not 1024 <= config.text_api_port <= 65535:
        raise AgentError("Invalid text API port")
    return config


def _safe_static_text(value: Any) -> str:
    text = str(value).strip()
    invalid_control = any(
        ord(char) < 32 and char not in "\t\n" for char in text
    )
    if not text or len(text) > REPLY_LIMIT or invalid_control:
        raise AgentError("Invalid static dialog text")
    return text


def _safe_system_prompt(value: Any) -> str:
    text = str(value).strip()
    invalid_control = any(ord(char) < 32 and char not in "\t\n" for char in text)
    if not text or len(text) > 32000 or invalid_control:
        raise AgentError("Invalid system prompt")
    return text


def _safe_identifier(value: Any, label: str, lease: bool = False) -> str:
    text = str(value or "").strip()
    pattern = LEASE_RE if lease else IDENTIFIER_RE
    if not pattern.fullmatch(text):
        raise ProtocolError(f"invalid_{label}")
    return text


def _safe_caller(value: Any) -> str:
    text = str(value or "").strip()
    if not PHONE_RE.fullmatch(text):
        return ""
    return text


def _safe_codec(value: Any) -> str:
    text = str(value or "").strip()
    if not re.fullmatch(r"[A-Za-z0-9_(),+./-]{0,128}", text):
        return ""
    return text


def _read_exact(sock: socket.socket | ssl.SSLSocket, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        block = sock.recv(size - len(data))
        if not block:
            raise ProtocolError("connection_closed")
        data.extend(block)
    return bytes(data)


class WebSocketClient:
    def __init__(self, url: str, timeout: float) -> None:
        self.url = url
        self.timeout = timeout
        self.sock: socket.socket | ssl.SSLSocket | None = None
        self.buffer = bytearray()

    def __enter__(self) -> "WebSocketClient":
        parsed = urlsplit(self.url)
        if parsed.scheme not in {"ws", "wss"} or not parsed.hostname:
            raise ProtocolError("invalid_websocket_url")
        secure = parsed.scheme == "wss"
        port = parsed.port or (443 if secure else 80)
        sock = socket.create_connection((parsed.hostname, port), timeout=self.timeout)
        if secure:
            sock = ssl.create_default_context().wrap_socket(sock, server_hostname=parsed.hostname)
        sock.settimeout(self.timeout)
        self.sock = sock
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        host = parsed.hostname if port == (443 if secure else 80) else f"{parsed.hostname}:{port}"
        request = (
            f"GET {path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\nUser-Agent: Kienzlefon-AI-Agent/2.5.1\r\n\r\n"
        ).encode("ascii")
        sock.sendall(request)
        header = self._read_header()
        lines = header.decode("iso-8859-1").split("\r\n")
        if not lines or " 101 " not in f" {lines[0]} ":
            raise ProtocolError("websocket_upgrade_failed")
        headers = {
            name.strip().lower(): value.strip()
            for line in lines[1:]
            if ":" in line
            for name, value in [line.split(":", 1)]
        }
        expected = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
        ).decode()
        if headers.get("sec-websocket-accept") != expected:
            raise ProtocolError("websocket_accept_invalid")
        connection_tokens = {
            token.strip().lower() for token in headers.get("connection", "").split(",")
        }
        if headers.get("upgrade", "").lower() != "websocket" or "upgrade" not in connection_tokens:
            raise ProtocolError("websocket_upgrade_headers_invalid")
        return self

    def _read_header(self) -> bytes:
        assert self.sock is not None
        while b"\r\n\r\n" not in self.buffer:
            if len(self.buffer) >= 65536:
                raise ProtocolError("websocket_header_too_large")
            block = self.sock.recv(4096)
            if not block:
                raise ProtocolError("websocket_closed_during_handshake")
            self.buffer.extend(block)
        end = self.buffer.index(b"\r\n\r\n") + 4
        header = bytes(self.buffer[:end])
        del self.buffer[:end]
        return header

    def _recv_exact(self, size: int) -> bytes:
        assert self.sock is not None
        while len(self.buffer) < size:
            block = self.sock.recv(max(4096, size - len(self.buffer)))
            if not block:
                raise ProtocolError("websocket_closed")
            self.buffer.extend(block)
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    def send(self, opcode: int, payload: bytes) -> None:
        assert self.sock is not None
        length = len(payload)
        if length < 126:
            length_bytes = bytes([0x80 | length])
        elif length <= 65535:
            length_bytes = bytes([0x80 | 126]) + struct.pack("!H", length)
        else:
            length_bytes = bytes([0x80 | 127]) + struct.pack("!Q", length)
        mask = os.urandom(4)
        masked = bytes(value ^ mask[index & 3] for index, value in enumerate(payload))
        self.sock.sendall(bytes([0x80 | opcode]) + length_bytes + mask + masked)

    def send_binary(self, payload: bytes) -> None:
        self.send(0x2, payload)

    def recv_json(self) -> Mapping[str, Any]:
        fragments = bytearray()
        message_opcode: int | None = None
        while True:
            first, second = self._recv_exact(2)
            final = bool(first & 0x80)
            opcode = first & 0x0F
            if first & 0x70:
                raise ProtocolError("websocket_reserved_bits_set")
            if second & 0x80:
                raise ProtocolError("masked_websocket_server_frame")
            length = second & 0x7F
            if length == 126:
                length = struct.unpack("!H", self._recv_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._recv_exact(8))[0]
            if length > 4 * 1024 * 1024:
                raise ProtocolError("websocket_message_too_large")
            payload = self._recv_exact(length) if length else b""
            if opcode >= 0x8 and (not final or length > 125):
                raise ProtocolError("websocket_control_frame_invalid")
            if opcode == 0x8:
                raise ProtocolError("websocket_closed_before_end")
            if opcode == 0x9:
                self.send(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            if opcode in {0x1, 0x2}:
                if message_opcode is not None:
                    raise ProtocolError("nested_websocket_fragments")
                message_opcode = opcode
                fragments.extend(payload)
            elif opcode == 0x0:
                if message_opcode is None:
                    raise ProtocolError("unexpected_websocket_continuation")
                fragments.extend(payload)
            else:
                raise ProtocolError("unsupported_websocket_opcode")
            if final:
                if message_opcode != 0x1:
                    raise ProtocolError("unexpected_binary_websocket_response")
                value = json.loads(bytes(fragments).decode("utf-8"))
                if not isinstance(value, Mapping):
                    raise ProtocolError("websocket_json_not_object")
                return value

    def __exit__(self, *_args: Any) -> None:
        if self.sock is not None:
            with contextlib.suppress(OSError):
                self.sock.shutdown(socket.SHUT_RDWR)
            with contextlib.suppress(OSError):
                self.sock.close()
            self.sock = None


class BandlimitedPCMResampler:
    """Stateful dependency-free mono S16LE windowed-sinc resampler."""

    def __init__(self, source_rate: int, target_rate: int) -> None:
        if source_rate <= 0 or target_rate <= 0:
            raise ValueError("sample rates must be positive")
        self.source_rate = source_rate
        self.target_rate = target_rate
        self.radius = 16
        self.cutoff = 0.5 * min(1.0, target_rate / source_rate) * 0.94
        self.samples: list[int] = []
        self.base_index = 0
        self.next_numerator = 0
        self.remainder = b""
        self._phases: dict[int, tuple[tuple[int, float], ...]] = {}

    def _coefficients(self, fraction_numerator: int) -> tuple[tuple[int, float], ...]:
        cached = self._phases.get(fraction_numerator)
        if cached is not None:
            return cached
        fraction = fraction_numerator / self.target_rate
        values: list[tuple[int, float]] = []
        for offset in range(-self.radius + 1, self.radius + 1):
            distance = fraction - offset
            position = abs(distance) / self.radius
            if position >= 1.0:
                weight = 0.0
            else:
                # Symmetric Blackman window around the interpolation point.
                window = (
                    0.42
                    + 0.5 * math.cos(math.pi * position)
                    + 0.08 * math.cos(2.0 * math.pi * position)
                )
                argument = 2.0 * self.cutoff * distance
                sinc = (
                    1.0
                    if abs(argument) < 1e-15
                    else math.sin(math.pi * argument) / (math.pi * argument)
                )
                weight = 2.0 * self.cutoff * sinc * window
            values.append((offset, weight))
        total = sum(weight for _offset, weight in values)
        if abs(total) < 1e-12:
            raise AgentError("resampler_filter_invalid")
        result = tuple((offset, weight / total) for offset, weight in values)
        self._phases[fraction_numerator] = result
        return result

    def feed(self, data: bytes, *, final: bool = False) -> bytes:
        combined = self.remainder + data
        self.remainder = combined[-1:] if len(combined) % 2 else b""
        usable = combined[: len(combined) - len(combined) % 2]
        if usable:
            values = array.array("h")
            values.frombytes(usable)
            if sys.byteorder != "little":
                values.byteswap()
            self.samples.extend(int(value) for value in values)

        output = array.array("h")
        end_index = self.base_index + len(self.samples)
        while self.samples:
            left_index, fraction_numerator = divmod(
                self.next_numerator, self.target_rate
            )
            if left_index >= end_index:
                break
            if not final and left_index + self.radius >= end_index:
                break
            weighted = 0.0
            available_weight = 0.0
            for offset, weight in self._coefficients(fraction_numerator):
                source_index = left_index + offset
                if source_index < 0 or source_index >= end_index:
                    continue
                local_index = source_index - self.base_index
                if local_index < 0:
                    raise AgentError("resampler_history_underflow")
                weighted += self.samples[local_index] * weight
                available_weight += weight
            if abs(available_weight) < 1e-12:
                raise AgentError("resampler_edge_filter_invalid")
            value = round(weighted / available_weight)
            output.append(max(-32768, min(32767, value)))
            self.next_numerator += self.source_rate

        if final:
            self.samples.clear()
            self.base_index = 0
            self.next_numerator = 0
            self.remainder = b""
        else:
            next_left = self.next_numerator // self.target_rate
            drop = min(
                max(0, next_left - self.radius + 1 - self.base_index),
                len(self.samples),
            )
            if drop:
                del self.samples[:drop]
                self.base_index += drop
        if sys.byteorder != "little":
            output.byteswap()
        return output.tobytes()


def pcm_resample(data: bytes, source_rate: int, target_rate: int) -> bytes:
    if source_rate == target_rate:
        return data[: len(data) - len(data) % 2]
    return BandlimitedPCMResampler(source_rate, target_rate).feed(data, final=True)


def asr_transcribe(
    config: AgentConfig,
    pcm_telephony: bytes,
    debug: DebugCallback | None = None,
) -> ASRResult:
    started = time.monotonic()
    utterance_ms = len(pcm_telephony) * 1000 // (TELEPHONY_RATE * PCM_WIDTH)
    debug_notify(debug, "asr_start", {
        "input_bytes": len(pcm_telephony),
        "utterance_ms": utterance_ms,
        "source_rate": TELEPHONY_RATE,
        "target_rate": ASR_RATE,
        "resampled": TELEPHONY_RATE != ASR_RATE,
    })
    partial_count = 0
    confirmed_count = 0
    connect_ms = 0
    try:
        pcm_16k = pcm_resample(pcm_telephony, TELEPHONY_RATE, ASR_RATE)
        assembler = ConfirmedTranscriptAssembler()
        connected = time.monotonic()
        with WebSocketClient(config.asr_url, config.asr_timeout) as ws:
            ready = ws.recv_json()
            audio = ready.get("audio")
            if (
                ready.get("type") != "ready"
                or ready.get("protocol") != "kienzlefon-asr-v1"
                or not isinstance(audio, Mapping)
                or audio.get("encoding") != "pcm_s16le"
                or audio.get("sample_rate") != ASR_RATE
                or audio.get("channels") != 1
            ):
                raise ProtocolError("asr_ready_contract_mismatch")
            connect_ms = round((time.monotonic() - connected) * 1000)
            debug_notify(debug, "asr_ready", {
                "connect_ms": connect_ms,
                "encoding": "pcm_s16le",
                "sample_rate": ASR_RATE,
                "channels": 1,
            })
            block_count = 0
            for offset in range(0, len(pcm_16k), 6400):
                ws.send_binary(pcm_16k[offset : offset + 6400])
                block_count += 1
            ws.send_binary(b"")
            debug_notify(debug, "asr_audio_sent", {
                "bytes": len(pcm_16k),
                "blocks": block_count,
                "block_size": 6400,
            })
            while True:
                event = ws.recv_json()
                kind = event.get("type")
                if kind == "confirmed":
                    text = event.get("text")
                    if isinstance(text, str):
                        if len(text) > TRANSCRIPT_LIMIT or "\x00" in text:
                            raise ProtocolError("asr_confirmed_text_invalid")
                        confirmed_count += 1
                        assembler.add(text, event.get("start"), event.get("end"))
                        debug_notify(
                            debug,
                            "asr_confirmed",
                            {"sequence": confirmed_count, "chars": len(text)},
                            {"text": text},
                        )
                elif kind == "partial":
                    partial_count += 1
                    partial = event.get("text")
                    valid_partial = (
                        isinstance(partial, str)
                        and len(partial) <= TRANSCRIPT_LIMIT
                        and "\x00" not in partial
                    )
                    debug_notify(
                        debug,
                        "asr_partial",
                        {
                            "sequence": partial_count,
                            "chars": len(partial) if valid_partial else 0,
                        },
                        {"text": partial} if valid_partial else None,
                    )
                elif kind == "ready":
                    continue
                elif kind == "end":
                    break
                elif kind == "error":
                    raise ProtocolError("asr_reported_error")
                else:
                    raise ProtocolError("unknown_asr_event")
        transcript = assembler.transcript()
        if not transcript:
            raise ProtocolError("asr_empty_confirmed_transcript")
        if len(transcript) > TRANSCRIPT_LIMIT:
            raise ProtocolError("asr_transcript_too_large")
        duration_ms = round((time.monotonic() - started) * 1000)
        debug_notify(debug, "asr_end", {
            "duration_ms": duration_ms,
            "partial_count": partial_count,
            "confirmed_count": confirmed_count,
            "confirmed_chars": len(transcript),
        })
        return ASRResult(
            transcript=transcript,
            duration_ms=duration_ms,
            connect_ms=connect_ms,
            partial_count=partial_count,
            confirmed_count=confirmed_count,
        )
    except Exception as error:
        debug_notify(debug, "asr_error", {
            "duration_ms": round((time.monotonic() - started) * 1000),
            "code": diagnostic_error_code(error),
            "partial_count": partial_count,
            "confirmed_count": confirmed_count,
        })
        raise


class AsyncASRWebSocket:
    """Cancellable standard-library transport for simultaneous audio/events."""

    def __init__(self, url: str, timeout: float) -> None:
        self.url = url
        self.timeout = timeout
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.write_lock = asyncio.Lock()

    async def open(self) -> None:
        parsed = urlsplit(self.url)
        if parsed.scheme not in {"ws", "wss"} or not parsed.hostname:
            raise ProtocolError("invalid_websocket_url")
        secure = parsed.scheme == "wss"
        port = parsed.port or (443 if secure else 80)
        async with asyncio.timeout(self.timeout):
            self.reader, self.writer = await asyncio.open_connection(
                parsed.hostname, port,
                ssl=ssl.create_default_context() if secure else None,
            )
            key = base64.b64encode(os.urandom(16)).decode("ascii")
            path = parsed.path or "/"
            if parsed.query:
                path += "?" + parsed.query
            host = parsed.hostname
            if ":" in host:
                host = f"[{host}]"
            host = f"{host}:{port}"
            self.writer.write((
                f"GET {path} HTTP/1.1\r\nHost: {host}\r\n"
                "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
                f"User-Agent: Kienzlefon-AI-Agent/{VERSION}\r\n\r\n"
            ).encode("ascii"))
            await self.writer.drain()
            header = await self.reader.readuntil(b"\r\n\r\n")
            lines = header.decode("iso-8859-1").split("\r\n")
            if len(lines[0].split()) < 2 or lines[0].split()[1] != "101":
                raise ProtocolError("websocket_upgrade_failed")
            headers = {
                name.strip().lower(): value.strip()
                for line in lines[1:] if ":" in line
                for name, value in [line.split(":", 1)]
            }
            expected = base64.b64encode(hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
            ).digest()).decode()
            if headers.get("sec-websocket-accept") != expected:
                raise ProtocolError("websocket_accept_invalid")
            if (
                headers.get("upgrade", "").lower() != "websocket"
                or "upgrade" not in {
                    token.strip().lower()
                    for token in headers.get("connection", "").split(",")
                }
            ):
                raise ProtocolError("websocket_upgrade_headers_invalid")

    async def send(self, opcode: int, payload: bytes) -> None:
        assert self.writer is not None
        length = len(payload)
        if length < 126:
            prefix = bytes([0x80 | length])
        elif length <= 65535:
            prefix = b"\xfe" + struct.pack("!H", length)
        else:
            prefix = b"\xff" + struct.pack("!Q", length)
        mask = os.urandom(4)
        masked = bytes(value ^ mask[index & 3] for index, value in enumerate(payload))
        async with self.write_lock:
            self.writer.write(bytes([0x80 | opcode]) + prefix + mask + masked)
            await self.writer.drain()

    async def recv_json(self) -> Mapping[str, Any]:
        assert self.reader is not None
        fragments = bytearray()
        message_opcode: int | None = None
        while True:
            first, second = await self.reader.readexactly(2)
            final, opcode = bool(first & 0x80), first & 0x0f
            if first & 0x70 or second & 0x80:
                raise ProtocolError("websocket_frame_invalid")
            length = second & 0x7f
            if length == 126:
                length = struct.unpack("!H", await self.reader.readexactly(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", await self.reader.readexactly(8))[0]
            if length + len(fragments) > 4 * 1024 * 1024:
                raise ProtocolError("websocket_message_too_large")
            if opcode >= 8 and (not final or length > 125):
                raise ProtocolError("websocket_control_frame_invalid")
            payload = await self.reader.readexactly(length)
            if opcode == 8:
                raise ProtocolError("websocket_closed_before_end")
            if opcode == 9:
                await self.send(10, payload)
                continue
            if opcode == 10:
                continue
            if opcode == 1 and message_opcode is None:
                message_opcode = opcode
            elif opcode != 0 or message_opcode is None:
                raise ProtocolError("websocket_fragment_invalid")
            fragments.extend(payload)
            if final:
                value = json.loads(fragments.decode("utf-8"))
                if not isinstance(value, Mapping):
                    raise ProtocolError("websocket_json_not_object")
                return value

    async def close(self) -> None:
        if self.writer is not None:
            self.writer.close()
            with contextlib.suppress(Exception):
                await asyncio.wait_for(self.writer.wait_closed(), 1.0)
            self.writer = None


class StreamingASRSession:
    """One utterance; hypotheses are provisional, only 'end' releases final text."""

    MAX_PENDING_FRAMES = 100  # 2 seconds of 20-ms PCM; fail closed on overload.

    def __init__(self, config: AgentConfig, debug: DebugCallback | None = None,
                 on_transcript: Callable[[str], None] | None = None,
                 post_endpoint: bool = False) -> None:
        self.config = config
        self.post_endpoint = post_endpoint
        self.debug = debug
        self.on_transcript = on_transcript
        self.pending: asyncio.Queue[bytes | None] = asyncio.Queue(self.MAX_PENDING_FRAMES)
        self.task: asyncio.Task[ASRResult] | None = None
        self.error: ProtocolError | None = None
        self.end_sent = False
        self.started = 0.0
        self.partial_count = 0
        self.confirmed_count = 0

    def start(self, preroll: bytes) -> None:
        if self.task is not None:
            raise ProtocolError("asr_stream_already_started")
        self.started = time.monotonic()
        self.task = asyncio.create_task(self._run(), name="asr-stream")
        self.feed(preroll)

    def feed(self, pcm: bytes) -> None:
        if self.error is not None or (self.task is not None and self.task.done()):
            return
        for offset in range(0, len(pcm), TELEPHONY_FRAME_BYTES):
            try:
                self.pending.put_nowait(pcm[offset:offset + TELEPHONY_FRAME_BYTES])
            except asyncio.QueueFull:
                self.error = ProtocolError("asr_audio_queue_overrun")
                if self.task is not None:
                    self.task.cancel()
                debug_notify(self.debug, "asr_error", {"code": "asr_audio_queue_overrun"})
                return

    async def _send_audio(self, ws: AsyncASRWebSocket) -> None:
        while True:
            frame = await self.pending.get()
            if frame is None:
                self.end_sent = True
                await ws.send(2, b"")
                return
            await ws.send(2, frame)

    async def _receive(self, ws: AsyncASRWebSocket) -> str:
        assembler = ConfirmedTranscriptAssembler()
        while True:
            event = await ws.recv_json()
            kind = event.get("type")
            if kind == "confirmed":
                text = event.get("text")
                if not isinstance(text, str) or len(text) > TRANSCRIPT_LIMIT or "\x00" in text:
                    raise ProtocolError("asr_confirmed_text_invalid")
                self.confirmed_count += 1
                assembler.add(text, event.get("start"), event.get("end"))
                if len(assembler.transcript()) > TRANSCRIPT_LIMIT:
                    raise ProtocolError("asr_transcript_too_large")
                if self.on_transcript is not None:
                    self.on_transcript(assembler.transcript())
                debug_notify(self.debug, "asr_confirmed", {
                    "sequence": self.confirmed_count, "chars": len(text),
                }, {"text": text})
            elif kind == "partial":
                self.partial_count += 1
                text = event.get("text")
                valid = isinstance(text, str) and len(text) <= TRANSCRIPT_LIMIT and "\x00" not in text
                if self.on_transcript is not None:
                    # Gateway partial is the unconfirmed suffix, never append it
                    # to the confirmed assembler or to conversation history.
                    hypothesis = " ".join(part for part in (
                        assembler.transcript(), text.strip() if valid else ""
                    ) if part)
                    self.on_transcript(hypothesis if valid and len(hypothesis) <= TRANSCRIPT_LIMIT else "")
                debug_notify(self.debug, "asr_partial", {
                    "sequence": self.partial_count, "chars": len(text) if valid else 0,
                }, {"text": text} if valid else None)
            elif kind == "end":
                if not self.end_sent:
                    raise ProtocolError("asr_end_before_endpoint")
                transcript = assembler.transcript()
                if not transcript:
                    raise ProtocolError("asr_empty_confirmed_transcript")
                return transcript
            elif kind == "ready":
                continue
            elif kind == "error":
                raise ProtocolError("asr_reported_error")
            else:
                raise ProtocolError("unknown_asr_event")

    async def _run(self) -> ASRResult:
        ws = AsyncASRWebSocket(self.config.asr_url, self.config.asr_timeout)
        tasks: list[asyncio.Task[Any]] = []
        debug_notify(self.debug, "asr_start", {
            "streaming": not self.post_endpoint, "source_rate": TELEPHONY_RATE, "target_rate": ASR_RATE,
        })
        try:
            # The endpoint owns the finalization timeout; this bounds the whole
            # session as a second guard even if the audio producer disappears.
            async with asyncio.timeout(
                self.config.maximum_utterance_ms / 1000 + 2 * self.config.asr_timeout
            ):
                await ws.open()
                ready = await asyncio.wait_for(ws.recv_json(), self.config.asr_timeout)
                audio = ready.get("audio")
                if (
                    ready.get("type") != "ready"
                    or ready.get("protocol") != "kienzlefon-asr-v1"
                    or not isinstance(audio, Mapping)
                    or audio.get("encoding") != "pcm_s16le"
                    or audio.get("sample_rate") != ASR_RATE
                    or audio.get("channels") != 1
                    or TELEPHONY_RATE != ASR_RATE
                ):
                    raise ProtocolError("asr_ready_contract_mismatch")
                connect_ms = round((time.monotonic() - self.started) * 1000)
                debug_notify(self.debug, "asr_ready", {"connect_ms": connect_ms})
                sender = asyncio.create_task(self._send_audio(ws), name="asr-sender")
                receiver = asyncio.create_task(self._receive(ws), name="asr-receiver")
                tasks = [sender, receiver]
                _, transcript = await asyncio.gather(sender, receiver)
                duration_ms = round((time.monotonic() - self.started) * 1000)
                debug_notify(self.debug, "asr_end", {
                    "duration_ms": duration_ms, "partial_count": self.partial_count,
                    "confirmed_count": self.confirmed_count, "confirmed_chars": len(transcript),
                })
                return ASRResult(
                    transcript, duration_ms, connect_ms,
                    self.partial_count, self.confirmed_count,
                )
        except Exception as error:
            debug_notify(self.debug, "asr_error", {
                "code": diagnostic_error_code(error),
                "duration_ms": round((time.monotonic() - self.started) * 1000),
            })
            raise
        finally:
            for task in tasks:
                task.cancel()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            await ws.close()

    async def finish(self) -> ASRResult:
        if self.error is not None:
            raise self.error
        if self.task is None:
            raise ProtocolError("asr_stream_not_started")
        if self.task.done():
            return self.task.result()
        try:
            async with asyncio.timeout(self.config.asr_timeout):
                await self.pending.put(None)
                return await self.task
        except TimeoutError as error:
            raise ProtocolError("asr_finalization_timeout") from error

    async def close(self) -> None:
        if self.task is not None:
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
        while not self.pending.empty():
            self.pending.get_nowait()


async def batch_asr_transcribe(config: AgentConfig, pcm: bytes,
                               debug: DebugCallback | None = None) -> ASRResult:
    """Upload only AFTER VAD collected the entire utterance; cancellable I/O.

    The gateway wire protocol is unchanged, but no audio is sent during speech.
    Backpressure rather than queue overflow permits long complete blocks.
    """
    session = StreamingASRSession(config, debug, post_endpoint=True)
    session.start(b"")

    async def upload() -> None:
        for offset in range(0, len(pcm), TELEPHONY_FRAME_BYTES):
            await session.pending.put(pcm[offset:offset + TELEPHONY_FRAME_BYTES])
        await session.pending.put(None)

    producer = asyncio.create_task(upload(), name="asr-block-upload")
    try:
        async with asyncio.timeout(config.asr_timeout):
            assert session.task is not None
            done, _ = await asyncio.wait({producer, session.task}, return_when=asyncio.FIRST_COMPLETED)
            if producer in done:
                await producer
            return await session.task
    except TimeoutError as error:
        raise ProtocolError("asr_finalization_timeout") from error
    finally:
        producer.cancel()
        await asyncio.gather(producer, return_exceptions=True)
        await session.close()


async def call_llm_async(config: AgentConfig, state: ConversationState,
                         transcript: str, policy: Mapping[str, Any]) -> LLMResult:
    payload = build_llm_payload(config, state, transcript, policy)
    envelope = await async_llm_envelope(config, payload)
    return decode_llm_envelope(envelope, state, transcript, policy)


def http_connection(url: str, timeout: float) -> tuple[http.client.HTTPConnection, str]:
    parsed = urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ProtocolError("invalid_http_url")
    cls = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
    connection = cls(parsed.hostname, parsed.port, timeout=timeout)
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    return connection, path


def llm_schema() -> dict[str, Any]:
    # Längen werden nach der Generierung strikt geprüft. Begrenzte String-
    # Wiederholungen vervielfachen die llama.cpp-GBNF-Regelkomplexität.
    field_properties = {name: {"type": "string"} for name in ALL_FIELDS}
    order_schema = {
        "type": "object",
        "additionalProperties": False,
        "required": ["complete", "call_type", "fields", "zusammenfassung"],
        "properties": {
            "complete": {"type": "boolean"},
            "call_type": {"enum": list(ALLOWED_CALL_TYPES)},
            "fields": {
                "type": "object",
                "additionalProperties": False,
                "required": list(ALL_FIELDS),
                "properties": field_properties,
            },
            "zusammenfassung": {"type": "string"},
        },
    }
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["reply", "caller_role", "urgency", "action", "orders"],
        "properties": {
            "reply": {"type": "string"},
            "caller_role": {"enum": list(ALLOWED_CALLER_ROLES)},
            "urgency": {"enum": list(ALLOWED_URGENCIES)},
            "action": {"enum": list(ALLOWED_ACTIONS)},
            "orders": {"type": "array", "items": order_schema},
        },
    }


def _valid_birth_date(value: str) -> bool:
    if not re.fullmatch(r"[0-9]{2}\.[0-9]{2}\.[0-9]{4}", value):
        return False
    try:
        return datetime.strptime(value, "%d.%m.%Y").strftime("%d.%m.%Y") == value
    except ValueError:
        return False


def order_payload(order: OrderState, include_internal: bool = False) -> dict[str, Any]:
    result: dict[str, Any] = {
        "complete": order.complete,
        "call_type": order.call_type,
        "fields": dict(order.fields),
        "zusammenfassung": order.zusammenfassung,
    }
    if include_internal:
        result.update({
            "order_id": order.order_id,
            "committed": order.committed,
            "call_id": order.call_id,
        })
    return result


def state_payload(state: ConversationState, policy: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "channel": state.channel,
        "caller_id": state.caller_id,
        "caller_phone_available": bool(state.caller_id),
        "action": state.action,
        "orders": [order_payload(order) for order in state.orders],
        "call_policy": dict(policy),
    }


_GENERIC_FINAL_QUESTIONS = (
    FINAL_CHECK_QUESTION,
    "Haben Sie noch ein weiteres Anliegen?",
    "Haben Sie noch weitere Anliegen?",
    "Kann ich sonst noch etwas für Sie tun?",
    "Kann ich Ihnen sonst noch helfen?",
)


def _strip_generic_final_question(reply: str) -> str:
    text = reply.strip()

    for ending in _GENERIC_FINAL_QUESTIONS:
        if text.endswith(ending):
            return text[:-len(ending)].rstrip()

    return text


def _reply_with_final_check(reply: str) -> str:
    text = _strip_generic_final_question(reply)

    if text:
        return f"{text} {FINAL_CHECK_QUESTION}"

    return FINAL_CHECK_QUESTION


_AU_TERM_RE = re.compile(
    r"(?i)(?<!\w)(?:au|arbeitsunfähigkeit(?:en)?|"
    r"arbeitsunfähigkeitsbescheinigung(?:en)?|krankschreib\w*)(?!\w)"
)
_AU_EXTENSION_RE = re.compile(
    r"(?i)(?:"
    r"(?:au|arbeitsunfähigkeit|arbeitsunfähigkeitsbescheinigung|krankschreib\w*).{0,40}\bverlänger\w*\b"
    r"|\bverlänger\w*\b.{0,40}(?:au|arbeitsunfähigkeit|arbeitsunfähigkeitsbescheinigung|krankschreib\w*)"
    r"|(?:au|arbeitsunfähigkeit|arbeitsunfähigkeitsbescheinigung|krankschreib\w*).{0,40}"
    r"\b(?:läuft|endet|gilt)\b.{0,24}\baus\b"
    r"|(?:au|arbeitsunfähigkeit|arbeitsunfähigkeitsbescheinigung|krankschreib\w*).{0,40}"
    r"\b(?:ausgelaufen|abgelaufen)\b"
    r"|\bfolgebescheinigung\b)"
)
_AU_NEGATION_RE = re.compile(
    r"(?i)\b(?:kein|keine|keinen|keiner|keines|nicht)\s+"
    r"(?:neue[nrsm]?\s+)?"
    r"(?:au|arbeitsunfähigkeit|arbeitsunfähigkeitsbescheinigung|krankschreib\w*)\b"
)
_AU_NEW_REQUEST_RE = re.compile(
    r"(?i)(?:\bkrank\s*schreib\w*\b|\bschreib\w*.{0,20}\bmich\s+krank\b)"
)
_EXPLICIT_TERMIN_RE = re.compile(r"(?i)\btermin\w*")
_EXPLICIT_UEB_RE = re.compile(r"(?i)\b(?:überweisung|ueberweisung)\w*")
_AU_YES_RE = re.compile(
    r"(?i)^\s*(?:ja\b|doch\b|gern(?:e)?\b|okay\b|ok\b|bitte\b|"
    r"machen\s+sie\s+das\b|das\s+wäre\s+gut\b|"
    r"(?:ich\s+)?(?:möchte|will)\b.*\brückruf\b)"
)
_AU_NO_RE = re.compile(
    r"(?i)(?:^\s*(?:nein|ne|nö)\b|\bkein(?:en)?\s+rückruf\b|"
    r"\bnicht\s+nötig\b|(?:ich\s+)?(?:komme|komm)\b.*(?:praxis|vorbei)|"
    r"(?:ich\s+)?(?:möchte|will)\b.*(?:persönlich|vorbei))"
)
_EXTERNAL_MESSAGE_RE = re.compile(
    r"(?i)\b(?:mitteil\w*|informier\w*|bescheid\s+geben|"
    r"ankündig\w*|ausricht\w*|weitergeb\w*)\b"
)
_EXTERNAL_DISMISSAL_RE = re.compile(
    r"(?i)(?:"
    r"(?:nicht|keine?)\b.{0,40}\b(?:aufgabe|zuständig|zuständigkeit|"
    r"angelegenheit)\b.{0,40}\bpraxis\b"
    r"|\bpraxis\b.{0,40}\bnicht\b.{0,20}\bzuständig\b"
    r"|\bwenden\s+sie\s+sich\b.{0,80}\ban\b)"
)


def detect_au_intent(transcript: str) -> str:
    if _AU_EXTENSION_RE.search(transcript):
        return "extension"
    if _AU_NEGATION_RE.search(transcript):
        return ""
    return (
        "new"
        if _AU_TERM_RE.search(transcript) or _AU_NEW_REQUEST_RE.search(transcript)
        else ""
    )


def _au_callback_decision(transcript: str) -> bool | None:
    if _AU_YES_RE.search(transcript):
        return True
    if _AU_NO_RE.search(transcript):
        return False
    return None


def _au_callback_prompt(mode: str) -> str:
    if mode == "extension":
        return (
            "Eine Verlängerung Ihrer Arbeitsunfähigkeitsbescheinigung muss mit der "
            "Praxis abgestimmt werden. Ich kann eine Rückrufbitte aufnehmen. "
            "Möchten Sie einen Rückruf?"
        )
    return (
        "Eine neue Arbeitsunfähigkeitsbescheinigung muss mindestens telefonisch "
        "mit der Praxis besprochen werden. Sie können während der Sprechzeiten in "
        "die Praxis kommen oder ich kann eine Rückrufbitte aufnehmen. Möchten Sie "
        "einen Rückruf?"
    )


def _order_mentions_au(order: OrderState) -> bool:
    text = " ".join((
        order.fields.get("anliegen", ""),
        order.fields.get("grund", ""),
        order.zusammenfassung,
    ))
    return bool(_AU_TERM_RE.search(text) or _AU_EXTENSION_RE.search(text))


def _strip_au_orders(orders: list[OrderState]) -> list[OrderState]:
    au_types = {
        "sonstiges", "termin", "ueb_req", "rueckruf_details",
        "rueckruf_tel_grund",
    }
    return [
        order
        for order in orders
        if order.committed
        or order.call_type not in au_types
        or not _order_mentions_au(order)
    ]


def _strip_spurious_au_side_orders(
    state: ConversationState,
    orders: list[OrderState],
    transcript: str,
) -> tuple[list[OrderState], tuple[str, ...]]:
    previous_ids = {order.order_id for order in state.orders}
    allow_termin = bool(_EXPLICIT_TERMIN_RE.search(transcript))
    allow_ueb = bool(_EXPLICIT_UEB_RE.search(transcript))
    repairs: list[str] = []
    kept: list[OrderState] = []

    for order in orders:
        if order.committed or order.order_id in previous_ids:
            kept.append(order)
        elif order.call_type == "termin" and not allow_termin:
            repairs.append("au_spurious_termin_removed")
        elif order.call_type == "ueb_req" and not allow_ueb:
            repairs.append("au_spurious_ueb_req_removed")
        else:
            kept.append(order)

    return kept, tuple(repairs)


def _strip_handled_au_reintroductions(
    state: ConversationState,
    orders: list[OrderState],
    transcript: str,
) -> tuple[list[OrderState], tuple[str, ...]]:
    previous_ids = {order.order_id for order in state.orders}
    allow_termin = bool(_EXPLICIT_TERMIN_RE.search(transcript))
    allow_ueb = bool(_EXPLICIT_UEB_RE.search(transcript))
    repairs: list[str] = []
    kept: list[OrderState] = []

    for order in orders:
        if order.committed or order.order_id in previous_ids:
            kept.append(order)
        elif order.call_type == "termin" and not allow_termin:
            repairs.append("au_handled_termin_removed")
        elif order.call_type == "ueb_req" and not allow_ueb:
            repairs.append("au_handled_ueb_req_removed")
        elif _order_mentions_au(order):
            repairs.append("au_handled_order_removed")
        else:
            kept.append(order)

    return kept, tuple(repairs)


def _open_order_question(orders: list[OrderState]) -> str:
    questions = {
        "vorname": "Wie ist Ihr Vorname?",
        "nachname": "Wie ist Ihr Nachname?",
        "geburtsdatum": "Wie ist Ihr Geburtsdatum?",
        "telefon": "Unter welcher Telefonnummer können wir Sie erreichen?",
        "medikamente": "Welche Medikamente möchten Sie bestellen?",
        "fachrichtung": "Für welche Fachrichtung benötigen Sie die Überweisung?",
        "grund": "Worum geht es bei diesem Anliegen?",
        "anliegen": "Welche Mitteilung möchten Sie der Praxis hinterlassen?",
    }
    for order in orders:
        if order.complete or order.committed:
            continue
        missing = [
            name
            for name in ALLOWED_CALL_TYPES[order.call_type]
            if not order.fields.get(name)
        ]
        if missing:
            return questions[missing[0]]
    return "Bitte ergänzen Sie noch die fehlende Angabe zu Ihrem anderen Anliegen."


def normalize_emergency_order(
    order: OrderState,
    transcript: str,
    caller_id: str,
) -> None:
    fields = dict(order.fields)
    content = (
        fields.get("anliegen", "")
        or fields.get("grund", "")
        or order.zusammenfassung
        or transcript.strip()
    )

    def prefixed(value: str, limit: int) -> str:
        text = (value or content).strip()
        if not text.upper().startswith("NOTFALL:"):
            text = f"NOTFALL: {text}"
        return text[:limit]

    fields["anliegen"] = prefixed(fields.get("anliegen", ""), FIELD_LIMIT)
    fields["grund"] = prefixed(fields.get("grund", ""), FIELD_LIMIT)
    if not fields.get("telefon") and caller_id:
        fields["telefon"] = caller_id
    order.fields = fields
    order.zusammenfassung = prefixed(order.zusammenfassung, SUMMARY_LIMIT)
    order.complete = True


def normalize_external_message_result(
    state: ConversationState,
    result: LLMResult,
    transcript: str,
) -> LLMResult:
    if (
        state.channel != "telephone"
        or state.pending_au
        or state.au_callback_pending
        or result.raw.get("urgency") == "emergency"
        or result.raw.get("caller_role") in {"care_service", "professional_urgent"}
        or result.action in ACTION_TARGETS
    ):
        return result

    caller_role = result.raw.get("caller_role")
    if caller_role not in {"other", "unknown"}:
        return result

    if caller_role == "other":
        completed_external = False
        for order in result.orders:
            if order.call_type != "sonstiges" or order.committed:
                continue
            content = (
                order.fields.get("anliegen", "")
                or order.fields.get("grund", "")
                or order.zusammenfassung
            ).strip()
            if not content:
                continue
            if not order.zusammenfassung:
                order.zusammenfassung = content[:SUMMARY_LIMIT]
            if not order.complete:
                order.complete = True
                completed_external = True

        if completed_external:
            return LLMResult(
                "Vielen Dank. Ich habe die Mitteilung für die Praxis aufgenommen.",
                "none",
                result.orders,
                result.raw,
                result.repairs + ("external_message_completed",),
            )

    if (
        _EXTERNAL_DISMISSAL_RE.search(result.reply)
        and any(
            order.call_type == "sonstiges" and (order.complete or order.committed)
            for order in result.orders
        )
    ):
        return LLMResult(
            "Vielen Dank. Ich habe die Mitteilung für die Praxis aufgenommen.",
            "none",
            result.orders,
            result.raw,
            result.repairs + ("external_message_reply_normalized",),
        )

    previous_by_id = {order.order_id: order for order in state.orders}
    if any(
        order.order_id not in previous_by_id
        or order.call_type != previous_by_id[order.order_id].call_type
        or order.fields != previous_by_id[order.order_id].fields
        or order.zusammenfassung != previous_by_id[order.order_id].zusammenfassung
        or order.complete != previous_by_id[order.order_id].complete
        for order in result.orders
    ):
        return result

    if not (
        _EXTERNAL_MESSAGE_RE.search(transcript)
        or _EXTERNAL_DISMISSAL_RE.search(result.reply)
    ):
        return result

    content = transcript.strip()
    if not content:
        return result

    fields = {name: "" for name in ALL_FIELDS}
    if state.caller_id:
        fields["telefon"] = state.caller_id
    fields["anliegen"] = content[:FIELD_LIMIT]
    fields["grund"] = content[:FIELD_LIMIT]
    order = OrderState(
        f"order-{state.next_order_number:03d}",
        "sonstiges",
        fields,
        content[:SUMMARY_LIMIT],
        True,
    )
    state.next_order_number += 1
    return LLMResult(
        "Vielen Dank. Ich habe die Mitteilung für die Praxis aufgenommen.",
        "none",
        [*result.orders, order],
        result.raw,
        result.repairs + ("external_message_lossless_recovered",),
    )


def normalize_au_result(
    state: ConversationState,
    result: LLMResult,
    transcript: str,
    policy: Mapping[str, Any],
) -> LLMResult:
    if state.channel != "telephone":
        return result

    if (
        result.raw.get("urgency") == "emergency"
        or result.raw.get("caller_role") in {"care_service", "professional_urgent"}
    ):
        state.pending_au = ""
        state.au_callback_pending = False
        return result

    if state.au_handled and not state.au_callback_pending:
        orders, handled_repairs = _strip_handled_au_reintroductions(
            state, result.orders, transcript
        )
        if handled_repairs:
            reply = (
                _open_order_question(orders)
                if any(not (order.complete or order.committed) for order in orders)
                else FINAL_CHECK_QUESTION
            )
            return LLMResult(
                reply,
                "none",
                orders,
                result.raw,
                result.repairs + handled_repairs,
            )
        return result

    if state.au_callback_pending:
        mode = state.pending_au
        decision = _au_callback_decision(transcript)
        orders = _strip_au_orders(result.orders)

        if decision is True:
            reason = (
                "Rückrufbitte wegen Verlängerung der Arbeitsunfähigkeitsbescheinigung."
                if mode == "extension"
                else "Rückrufbitte wegen neuer Arbeitsunfähigkeitsbescheinigung."
            )
            fields = {name: "" for name in ALL_FIELDS}
            for order in [*state.orders, *orders]:
                for name in ("vorname", "nachname", "geburtsdatum", "telefon"):
                    if order.fields.get(name):
                        fields[name] = order.fields[name]
            if not fields["telefon"] and state.caller_id:
                fields["telefon"] = state.caller_id
            fields["grund"] = reason
            callback = OrderState(
                f"order-{state.next_order_number:03d}",
                "rueckruf_details",
                fields,
                reason,
                False,
            )
            state.next_order_number += 1
            orders.append(callback)

            missing = [
                name
                for name in ALLOWED_CALL_TYPES["rueckruf_details"]
                if not callback.fields.get(name)
            ]
            callback.complete = not missing
            reply = (
                {
                    "vorname": "Wie ist Ihr Vorname?",
                    "nachname": "Wie ist Ihr Nachname?",
                    "geburtsdatum": "Wie ist Ihr Geburtsdatum?",
                }[missing[0]]
                if missing
                else FINAL_CHECK_QUESTION
            )
            state.pending_au = ""
            state.au_callback_pending = False
            state.au_handled = True
            return LLMResult(
                reply,
                "none",
                orders,
                result.raw,
                result.repairs + ("au_callback_accepted",),
            )

        if decision is False:
            previous_by_id = {order.order_id: order for order in state.orders}
            personal_visit = bool(
                re.search(
                    r"(?i)(?:komme|komm|möchte|will).{0,40}(?:praxis|persönlich|vorbei)",
                    transcript,
                )
            )
            if personal_visit:
                orders = [
                    order
                    for order in orders
                    if order.order_id in previous_by_id
                    or order.committed
                    or order.call_type != "termin"
                ]

            changed_work = any(
                order.order_id not in previous_by_id
                or order.call_type != previous_by_id[order.order_id].call_type
                or order.fields != previous_by_id[order.order_id].fields
                or order.complete != previous_by_id[order.order_id].complete
                for order in orders
            )
            state.pending_au = ""
            state.au_callback_pending = False
            state.au_handled = True
            if changed_work:
                return LLMResult(
                    result.reply,
                    "none",
                    orders,
                    result.raw,
                    result.repairs + ("au_callback_declined_with_work",),
                )
            return LLMResult(
                FINAL_CHECK_QUESTION,
                "none",
                orders,
                result.raw,
                result.repairs + ("au_callback_declined",),
            )

        if any(not (order.complete or order.committed) for order in orders):
            return LLMResult(
                result.reply,
                "none",
                orders,
                result.raw,
                result.repairs + ("au_callback_waiting_with_open_order",),
            )
        return LLMResult(
            _au_callback_prompt(mode),
            "none",
            orders,
            result.raw,
            result.repairs + ("au_callback_reasked",),
        )

    if state.pending_au not in {"new", "extension"}:
        return result

    orders = _strip_au_orders(result.orders)
    orders, side_repairs = _strip_spurious_au_side_orders(
        state, orders, transcript
    )
    if any(not (order.complete or order.committed) for order in orders):
        reply = result.reply
        repairs = result.repairs + side_repairs + ("au_deferred_for_open_order",)
        if _AU_TERM_RE.search(reply) or _AU_NEW_REQUEST_RE.search(reply):
            reply = _open_order_question(orders)
            repairs += ("au_reply_suppressed_for_open_order",)
        return LLMResult(
            reply,
            "none",
            orders,
            result.raw,
            repairs,
        )

    mode = state.pending_au
    if policy.get("practice_queue_allowed") is True:
        state.pending_au = ""
        state.au_callback_pending = False
        state.au_handled = True
        reply = (
            "Eine Verlängerung Ihrer Arbeitsunfähigkeitsbescheinigung muss mit "
            "der Praxis abgestimmt werden. Ich stelle Sie jetzt durch."
            if mode == "extension"
            else
            "Eine neue Arbeitsunfähigkeitsbescheinigung muss mindestens "
            "telefonisch mit der Praxis besprochen werden. Ich stelle Sie jetzt durch."
        )
        return LLMResult(
            reply,
            "warteschlange",
            orders,
            result.raw,
            result.repairs + side_repairs + ("au_handoff",),
        )

    state.au_callback_pending = True
    return LLMResult(
        _au_callback_prompt(mode),
        "none",
        orders,
        result.raw,
        result.repairs + side_repairs + ("au_callback_offered",),
    )


def _merge_orders(
    previous: ConversationState, proposed: list[OrderState]
) -> list[OrderState]:
    used_ids: set[str] = set()
    replacements: dict[str, OrderState] = {}
    new_orders: list[OrderState] = []
    for order in proposed:
        candidates = [
            old
            for old in previous.orders
            if old.call_type == order.call_type and old.order_id not in used_ids
        ]
        old = next(
            (
                candidate
                for candidate in candidates
                if candidate.fields == order.fields
                and (
                    candidate.complete
                    or candidate.committed
                    or candidate.zusammenfassung == order.zusammenfassung
                )
            ),
            None,
        )
        if old is None:
            old = next(
                (
                    candidate
                    for candidate in candidates
                    if not candidate.complete and not candidate.committed
                ),
                None,
            )

        # correction_window:
        # Nur die Order, die unmittelbar den aktuellen Final-Check
        # ausgelöst hat, darf trotz complete=true noch korrigiert
        # werden. Bereits committede Orders bleiben unveränderlich.
        if old is None and previous.final_check_order_ids:
            old = next(
                (
                    candidate
                    for candidate in candidates
                    if candidate.order_id in previous.final_check_order_ids
                    and candidate.complete
                    and not candidate.committed
                ),
                None,
            )

        if old is not None:
            used_ids.add(old.order_id)

            if old.committed or (
                old.complete
                and old.order_id not in previous.final_check_order_ids
            ):
                replacements[old.order_id] = old
                continue

            # preserve_known_fields_on_incomplete_merge:
            #
            # Nur stabile Personen-/Kontaktdaten werden gegen einen
            # versehentlichen leeren LLM-Wert geschützt.
            #
            # Inhaltliche Felder wie Medikamente, Fachrichtung, Grund
            # und Anliegen bleiben vollständig durch spätere Turns
            # korrigierbar.
            #
            # Nichtleere neue Werte gewinnen immer.
            PERSISTENT_FIELDS = (
                "vorname",
                "nachname",
                "geburtsdatum",
                "telefon",
            )

            for name in PERSISTENT_FIELDS:
                if not order.fields.get(name) and old.fields.get(name):
                    order.fields[name] = old.fields[name]

            # Eine vorübergehend leere Zusammenfassung darf weiterhin
            # den bereits vorhandenen Arbeitsstand nicht löschen.
            if not order.zusammenfassung and old.zusammenfassung:
                order.zusammenfassung = old.zusammenfassung

            order.order_id = old.order_id
            replacements[old.order_id] = order
        else:
            order.order_id = f"order-{previous.next_order_number:03d}"
            previous.next_order_number += 1
            new_orders.append(order)
    merged: list[OrderState] = []
    for old in previous.orders:
        if old.order_id in replacements:
            merged.append(replacements[old.order_id])
        elif old.complete or old.committed:
            merged.append(old)
    merged.extend(new_orders)
    return merged


def validate_llm_result(
    value: Any,
    previous: ConversationState,
    policy: Mapping[str, Any],
) -> LLMResult:
    if not isinstance(value, Mapping):
        raise ProtocolError("llm_json_shape_invalid")

    keys = set(value)
    live_keys = {"reply", "caller_role", "urgency", "action", "orders"}
    legacy_keys = {"reply", "action", "orders"}

    if keys == live_keys:
        caller_role = value["caller_role"]
        urgency = value["urgency"]
    elif keys == legacy_keys:
        # Nur für vorhandene interne Alt-Tests.
        # Das Live-LLM wird durch das Strict Schema auf live_keys verpflichtet.
        caller_role = "unknown"
        urgency = "normal"
    else:
        raise ProtocolError("llm_json_shape_invalid")

    if caller_role not in ALLOWED_CALLER_ROLES:
        raise ProtocolError("llm_caller_role_invalid")
    if urgency not in ALLOWED_URGENCIES:
        raise ProtocolError("llm_urgency_invalid")

    reply, action, raw_orders = value["reply"], value["action"], value["orders"]
    if (
        not isinstance(reply, str)
        or not reply.strip()
        or len(reply) > REPLY_LIMIT
        or "\x00" in reply
    ):
        raise ProtocolError("llm_reply_invalid")
    if action not in ALLOWED_ACTIONS:
        raise ProtocolError("llm_action_invalid")
    if not isinstance(raw_orders, list) or len(raw_orders) > 32:
        raise ProtocolError("llm_orders_invalid")

    repairs: list[str] = []
    proposed: list[OrderState] = []
    for index, raw_order in enumerate(raw_orders):
        if (
            not isinstance(raw_order, Mapping)
            or set(raw_order) != {"complete", "call_type", "fields", "zusammenfassung"}
        ):
            raise ProtocolError("llm_order_shape_invalid")
        complete = raw_order["complete"]
        call_type = raw_order["call_type"]
        fields = raw_order["fields"]
        summary = raw_order["zusammenfassung"]
        if not isinstance(complete, bool):
            raise ProtocolError("llm_order_complete_invalid")
        if call_type not in ALLOWED_CALL_TYPES:
            raise ProtocolError("llm_call_type_invalid")
        if not isinstance(fields, Mapping) or set(fields) != set(ALL_FIELDS):
            raise ProtocolError("llm_fields_invalid")
        if (
            not isinstance(summary, str)
            or len(summary) > SUMMARY_LIMIT
            or "\x00" in summary
        ):
            raise ProtocolError("llm_summary_invalid")
        cleaned: dict[str, str] = {}
        for name in ALL_FIELDS:
            text = fields[name]
            if not isinstance(text, str) or len(text) > FIELD_LIMIT or "\x00" in text:
                raise ProtocolError("llm_field_value_invalid")
            cleaned[name] = text.strip()
        if cleaned["telefon"] and not PHONE_RE.fullmatch(cleaned["telefon"]):
            raise ProtocolError("llm_phone_value_invalid")
        if not cleaned["telefon"] and previous.caller_id:
            cleaned["telefon"] = previous.caller_id
        if cleaned["geburtsdatum"] and not _valid_birth_date(cleaned["geburtsdatum"]):
            cleaned["geburtsdatum"] = ""
            complete = False
            repairs.append(f"order_{index}_birth_date_invalid")
        if call_type == "sonstiges":
            content = (
                cleaned["anliegen"]
                or cleaned["grund"]
                or summary.strip()
            )
            if content:
                content = content[:FIELD_LIMIT]
                if not cleaned["anliegen"]:
                    cleaned["anliegen"] = content
                    repairs.append(
                        f"order_{index}_sonstiges_anliegen_recovered"
                    )
                if not cleaned["grund"]:
                    cleaned["grund"] = content
                    repairs.append(
                        f"order_{index}_sonstiges_grund_recovered"
                    )

        missing = [name for name in ALLOWED_CALL_TYPES[call_type] if not cleaned[name]]
        if complete and (missing or not summary.strip()):
            complete = False
            repairs.append(f"order_{index}_complete_downgraded")
        proposed.append(
            OrderState("", call_type, cleaned, summary.strip(), complete)
        )

    preserve_incomplete_on_empty = (
        not proposed
        and any(
            not (order.complete or order.committed)
            for order in previous.orders
        )
    )

    if previous.channel == "telephone" and urgency == "emergency":
        current_emergency_orders = [
            order
            for order in proposed
            if order.call_type == "sonstiges"
            and (
                order.fields.get("anliegen")
                or order.fields.get("grund")
                or order.zusammenfassung
            )
        ]
        if len(current_emergency_orders) == 1:
            normalize_emergency_order(
                current_emergency_orders[0],
                "",
                previous.caller_id,
            )
            repairs.append("emergency_existing_order_normalized")

    if preserve_incomplete_on_empty:
        # Ein einzelner LLM-Turn mit orders=[] darf den bereits
        # bestätigten unvollständigen Arbeitszustand nicht löschen.
        #
        # Sobald das LLM einen neuen/anderen Auftrag liefert,
        # greift wieder unverändert _merge_orders().
        merged = list(previous.orders)
        repairs.append(
            "empty_proposal_preserved_incomplete_orders"
        )
    else:
        merged = _merge_orders(previous, proposed)

    # v1.8:
    # LLM = semantische Klassifikation.
    # Backend = technische Spezialroute.
    if previous.channel == "telephone":
        staffed = (
            policy.get("practice_open") is True
            or policy.get("phone_open") is True
        )

        if urgency == "emergency":
            # Akuter Patienten-/Laiennotfall:
            # immer hoher Weiterleitungsversuch.
            # NOTFALL-Bericht des LLM bleibt erhalten.
            action = "rotes_telefon"

            if staffed:
                reply = (
                    "Das hört sich nicht gut an, vielleicht sollten Sie besser "
                    "auflegen und die 112 wählen? "
                    "Ich stelle Sie jetzt sofort durch!"
                )
            else:
                reply = (
                    "Das hört sich nicht gut an, vielleicht sollten Sie besser "
                    "auflegen und die 112 wählen? "
                    "Um diese Zeit ist zwar vermutlich niemand in der Praxis, "
                    "ich stelle Sie jetzt trotzdem sofort durch!"
                )

            repairs.append("role_route_patient_emergency")

        elif caller_role == "care_service":
            if policy.get("pharmacy_transfer_allowed") is True:
                # Erkannte Apotheke während freigegebener Zeit:
                # immer Apothekenwarteschlange und kein Rückrufauftrag.
                action = "priorisierung"
                merged = [
                    order
                    for order in previous.orders
                    if order.complete or order.committed
                ]
                reply = (
                    "Ich stelle Sie jetzt durch."
                    if staffed
                    else (
                        "Um diese Zeit ist zwar vermutlich niemand in der Praxis, "
                        "ich stelle Sie jetzt trotzdem sofort durch."
                    )
                )
                repairs.append(
                    "role_route_care_service"
                    if staffed
                    else "role_route_care_service_outside_hours"
                )

            elif action != "beenden":
                # Außerhalb der Weiterleitungszeit bleibt die inhaltliche
                # Rückrufaufnahme Aufgabe des LLM.
                action = "none"

                # Für eine erkannte Apotheke gibt es pro Gespräch genau einen
                # noch nicht committeden Fallback-Rückruf. Das LLM darf dessen
                # Inhalt in späteren Turns aktualisieren, aber keinen zweiten
                # parallelen Rückrufauftrag erzeugen.
                callbacks = [
                    order
                    for order in merged
                    if order.call_type == "rueckruf_tel_grund"
                    and not order.committed
                ]

                callback = callbacks[-1] if callbacks else None

                if len(callbacks) > 1:
                    # Neuester LLM-Stand gewinnt; stabile ID des ersten
                    # Fallback-Auftrags beibehalten.
                    callback.order_id = callbacks[0].order_id
                    callback_ids = {id(order) for order in callbacks}
                    merged = [
                        order
                        for order in merged
                        if id(order) not in callback_ids
                    ]
                    merged.append(callback)
                    repairs.append("care_service_callback_deduplicated")

                if callback is not None and callback.fields.get("telefon"):
                    # CLIP wurde vom bestehenden Normalizer bereits eingesetzt.
                    # rueckruf_tel_grund benötigt nur telefon als Pflichtfeld.
                    if not callback.complete:
                        callback.complete = True
                        repairs.append("care_service_callback_completed_from_clip")

                    # Zusammenfassung darf nicht behaupten, es sei keine
                    # Telefonnummer vorhanden, wenn die CLIP übernommen wurde.
                    callback.zusammenfassung = callback.zusammenfassung.replace(
                        "Telefonnummer noch nicht übermittelt.",
                        "Rufnummer aus der Anruferkennung übernommen.",
                    )

                    reply = (
                        "Die Praxis ist gerade nicht direkt erreichbar. "
                        "Ich nehme eine Rückrufbitte auf."
                    )

                repairs.append("role_route_care_service_callback")

        elif caller_role == "professional_urgent":
            # Arzt/Arztpraxis, Krankenhaus, Rettungsdienst, Notarzt:
            # höchste Priorität, aber nur während der von Kienzlefon Klassik
            # über specialist_transfer_allowed freigegebenen Zeit.
            if policy.get("specialist_transfer_allowed") is True:
                action = "rotes_telefon"
                merged = [
                    order
                    for order in previous.orders
                    if order.complete or order.committed
                ]
                reply = (
                    "Ich stelle Sie jetzt sofort durch."
                    if staffed
                    else (
                        "Um diese Zeit ist zwar vermutlich niemand in der Praxis, "
                        "ich stelle Sie jetzt trotzdem sofort durch."
                    )
                )
                repairs.append(
                    "role_route_professional_urgent"
                    if staffed
                    else "role_route_professional_urgent_outside_hours"
                )
            elif action != "beenden":
                # Außerhalb der konfigurierten Zeit keine Spezialweiterleitung.
                # Ein vom LLM erzeugter FACHANRUFER-Bericht bleibt erhalten.
                action = "none"
                reply = "Eine direkte Weiterleitung ist aktuell nicht möglich."
                repairs.append("role_route_professional_urgent_blocked")

        elif action in {"priorisierung", "rotes_telefon"}:
            # Ohne sichere Rollen-/Notfallklassifikation keine Spezialroute.
            action = "none"
            reply = "Eine direkte Spezialweiterleitung ist hier nicht vorgesehen."
            repairs.append("role_route_special_rejected")

    if action in ACTION_TARGETS:
        if previous.channel == "chat":
            action = "none"
            reply = (
                "Eine telefonische Weiterleitung ist im Chat nicht möglich. "
                "Bitte wenden Sie sich telefonisch an die Praxis."
            )
            repairs.append("chat_transfer_rejected")
        elif (
            action != "rotes_telefon"
            and any(order.complete or order.committed for order in merged)
            and "role_route_care_service" not in repairs
            and "role_route_care_service_outside_hours" not in repairs
        ):
            action = "none"
            reply = (
                "Eine Weiterleitung ist in diesem Gespräch nicht möglich. "
                "Kann ich sonst noch etwas für Sie tun?"
            )
            repairs.append("transfer_with_order_rejected")
        elif (
            action != "rotes_telefon"
            and policy.get(ACTION_POLICY_FIELDS[action]) is not True
        ):
            requested_action = action
            action = "none"
            if requested_action == "priorisierung":
                reply = "Die Praxis ist gerade nicht direkt erreichbar."
                repairs.append("pharmacy_transfer_policy_rejected")
            else:
                reply = (
                    "Diese Weiterleitung ist aktuell nicht verfügbar. "
                    "Kann ich Ihnen noch anders helfen?"
                )
                repairs.append("transfer_policy_rejected")

    raw_copy = json.loads(json.dumps(value, ensure_ascii=False))
    return LLMResult(reply.strip(), action, merged, raw_copy, tuple(repairs))


def normalize_final_check_result(
    state: ConversationState,
    result: LLMResult,
) -> LLMResult:
    if state.channel != "telephone":
        return result

    if "au_callback_offered" in result.repairs or "au_callback_reasked" in result.repairs:
        state.final_check = False
        state.final_check_order_ids = ()
        return result

    if "au_callback_declined" in result.repairs:
        state.final_check = True
        state.final_check_order_ids = tuple(
            order.order_id
            for order in result.orders
            if (order.complete or order.committed) and not order.committed
        )
        return result

    previous_by_id = {
        order.order_id: order
        for order in state.orders
    }

    existing_order_ids = set(previous_by_id)

    previously_complete_ids = {
        order.order_id
        for order in state.orders
        if order.complete or order.committed
    }

    new_order_started = any(
        order.order_id not in existing_order_ids
        for order in result.orders
    )

    completed_now_ids = tuple(
        order.order_id
        for order in result.orders
        if (order.complete or order.committed)
        and order.order_id not in previously_complete_ids
    )

    has_incomplete_order = any(
        not (order.complete or order.committed)
        for order in result.orders
    )

    final_target_ids = set(state.final_check_order_ids)

    # Eine echte Korrektur ändert strukturierte Auftragsdaten.
    # Eine bloß anders formulierte Zusammenfassung zählt bewusst
    # NICHT als Korrektur.
    corrected_ids = tuple(
        order.order_id
        for order in result.orders
        if order.order_id in final_target_ids
        and order.order_id in previous_by_id
        and not previous_by_id[order.order_id].committed
        and (
            order.call_type
            != previous_by_id[order.order_id].call_type
            or order.fields
            != previous_by_id[order.order_id].fields
            or order.complete
            != previous_by_id[order.order_id].complete
        )
    )

    # --------------------------------------------------------
    # Antwort auf:
    # "Haben Sie noch ein Anliegen?"
    # --------------------------------------------------------
    if state.final_check:
        state.final_check = False
        state.final_check_order_ids = ()

        # Technische Spezialroute hat Vorrang.
        if result.action in ACTION_TARGETS:
            return result

        # Korrektur der gerade abgeschlossenen Order oder
        # tatsächlich neuer Auftrag:
        # Gespräch bleibt offen.
        if corrected_ids or new_order_started:
            if result.action == "beenden":
                result = LLMResult(
                    reply=result.reply,
                    action="none",
                    orders=result.orders,
                    raw=result.raw,
                    repairs=(
                        result.repairs
                        + ("final_check_changed_work_kept_open",)
                    ),
                )

            # Wenn nach Korrektur/neuem Anliegen bereits wieder alle
            # Arbeiten vollständig sind, genau einmal erneut fragen.
            if not has_incomplete_order:
                next_final_ids: list[str] = []

                for order_id in corrected_ids + completed_now_ids:
                    if order_id not in next_final_ids:
                        next_final_ids.append(order_id)

                if next_final_ids:
                    state.final_check = True
                    state.final_check_order_ids = tuple(next_final_ids)

                    return LLMResult(
                        reply=_reply_with_final_check(result.reply),
                        action="none",
                        orders=result.orders,
                        raw=result.raw,
                        repairs=(
                            result.repairs
                            + (
                                "final_check_restarted_after_change",
                            )
                        ),
                    )

            return result

        # Kein neuer Vorgang und keine strukturierte Korrektur:
        # Gespräch deterministisch beenden.
        return LLMResult(
            reply=FINAL_FAREWELL,
            action="beenden",
            orders=result.orders,
            raw=result.raw,
            repairs=(
                result.repairs
                + ("final_check_no_new_order_end",)
            ),
        )

    # --------------------------------------------------------
    # Normaler Arbeitsturn:
    # neu vollständig gewordene Order(s) öffnen das Korrektur-
    # fenster bis zur Antwort auf die Backend-Abschlussfrage.
    # --------------------------------------------------------
    if (
        completed_now_ids
        and not has_incomplete_order
        and result.action not in ACTION_TARGETS
    ):
        state.final_check = True
        state.final_check_order_ids = completed_now_ids

        return LLMResult(
            reply=_reply_with_final_check(result.reply),
            action="none",
            orders=result.orders,
            raw=result.raw,
            repairs=(
                result.repairs
                + ("final_check_started",)
            ),
        )

    return result


def ensure_emergency_record(
    state: ConversationState,
    transcript: str,
) -> None:
    """Ein erkannter Notfall besitzt immer einen persistierbaren Datensatz."""
    emergency = next(
        (
            order
            for order in state.orders
            if not order.committed
            and order.call_type == "sonstiges"
            and any(
                value.lstrip().upper().startswith("NOTFALL:")
                for value in (
                    order.fields.get("anliegen", ""),
                    order.fields.get("grund", ""),
                    order.zusammenfassung,
                )
            )
        ),
        None,
    )

    if emergency is None:
        fields = {name: "" for name in ALL_FIELDS}
        if state.caller_id:
            fields["telefon"] = state.caller_id

        fallback = f"NOTFALL: {transcript.strip()}"
        fields["anliegen"] = fallback[:FIELD_LIMIT]
        fields["grund"] = fallback[:FIELD_LIMIT]
        emergency = OrderState(
            f"order-{state.next_order_number}",
            "sonstiges",
            fields,
            fallback[:SUMMARY_LIMIT],
            True,
        )
        state.next_order_number += 1
        state.orders.append(emergency)

    normalize_emergency_order(
        emergency,
        transcript,
        state.caller_id,
    )


def ensure_uncertain_handoff_record(
    state: ConversationState,
    transcript: str,
    caller_role: str,
) -> None:
    """
    Eine Weiterleitung außerhalb der normalen besetzten Zeit darf
    niemals die einzige Kopie des Anliegens sein.
    """

    if caller_role == "professional_urgent":
        prefix = "FACHANRUFER:"
    elif caller_role == "care_service":
        prefix = "VERSORGUNGSPARTNER:"
    else:
        return

    spoken = transcript.strip()
    content = f"{prefix} {spoken}".strip()

    # Bereits vorhandenen passenden Sicherungsdatensatz nicht duplizieren.
    for order in state.orders:
        if order.committed or order.call_type != "sonstiges":
            continue

        values = (
            order.fields.get("anliegen", ""),
            order.fields.get("grund", ""),
            order.zusammenfassung,
        )

        if any(
            value.lstrip().upper().startswith(prefix)
            for value in values
        ):
            order.complete = True
            return

    fields = {name: "" for name in ALL_FIELDS}

    if state.caller_id:
        fields["telefon"] = state.caller_id

    fields["anliegen"] = content[:FIELD_LIMIT]
    fields["grund"] = content[:FIELD_LIMIT]

    order = OrderState(
        f"order-{state.next_order_number}",
        "sonstiges",
        fields,
        content[:SUMMARY_LIMIT],
        True,
    )

    state.next_order_number += 1
    state.orders.append(order)


def prepare_lossless_terminal_orders(
    state: ConversationState,
) -> None:
    """
    Am tatsächlichen Gesprächsende gilt:
    fehlendes Feld ist besser als verlorener Inhalt.

    Vollständige Aufträge bleiben unverändert.
    Unvollständige, aber inhaltlich verwertbare Aufträge werden als
    sonstiges-Rettungsdatensatz persistierbar gemacht.
    """
    for order in state.orders:
        if order.committed or order.complete:
            continue

        fields = {
            name: str(order.fields.get(name, "")).strip()
            for name in ALL_FIELDS
        }
        summary = order.zusammenfassung.strip()

        if not any(fields.values()) and not summary:
            # Tatsächlich kein verwertbarer Auftrag.
            continue

        original_type = order.call_type

        if original_type == "sonstiges":
            content = (
                fields["anliegen"]
                or fields["grund"]
                or summary
            )
            if not content:
                continue

            fields["anliegen"] = (
                fields["anliegen"] or content
            )[:FIELD_LIMIT]
            fields["grund"] = (
                fields["grund"] or content
            )[:FIELD_LIMIT]

            if not summary:
                summary = f"UNVOLLSTÄNDIG: {content}"

            order.fields = fields
            order.zusammenfassung = summary[:SUMMARY_LIMIT]
            order.complete = True
            continue

        missing = [
            name
            for name in ALLOWED_CALL_TYPES[original_type]
            if not fields.get(name)
        ]

        known = [
            f"{name}={value}"
            for name, value in fields.items()
            if value
        ]

        parts = [f"UNVOLLSTÄNDIGER {original_type}-Auftrag"]

        if missing:
            parts.append("fehlend: " + ", ".join(missing))

        if summary:
            parts.append("Inhalt: " + summary)

        if known:
            parts.append("Vorhandene Angaben: " + "; ".join(known))

        rescue_text = ". ".join(parts)

        # Originalfelder bleiben bestehen; dadurch gehen auch Informationen
        # verloren, die nicht in die 2000 Zeichen von anliegen passen würden.
        fields["anliegen"] = rescue_text[:FIELD_LIMIT]
        if not fields["grund"]:
            fields["grund"] = rescue_text[:FIELD_LIMIT]

        order.call_type = "sonstiges"
        order.fields = fields
        order.zusammenfassung = (
            "UNVOLLSTÄNDIG: " + (summary or rescue_text)
        )[:SUMMARY_LIMIT]
        order.complete = True


def apply_llm_result(
    state: ConversationState, result: LLMResult, transcript: str
) -> None:
    state.orders = result.orders
    for order in result.orders:
        match = re.fullmatch(r"order-([0-9]+)", order.order_id)
        if match:
            state.next_order_number = max(
                state.next_order_number, int(match.group(1)) + 1
            )
    state.action = result.action
    state.messages.extend(
        [
            {"role": "user", "content": transcript},
            {"role": "assistant", "content": result.reply},
        ]
    )

    if "role_route_patient_emergency" in result.repairs:
        ensure_emergency_record(state, transcript)

    if "role_route_professional_urgent_outside_hours" in result.repairs:
        ensure_uncertain_handoff_record(
            state,
            transcript,
            "professional_urgent",
        )

    if "role_route_care_service_outside_hours" in result.repairs:
        ensure_uncertain_handoff_record(
            state,
            transcript,
            "care_service",
        )


def validate_call_policy(value: Any) -> dict[str, Any]:
    required = {
        "protocol", "evaluated_at", "valid_for_ms", "timezone",
        "practice_open", "phone_open", "greeting_open", "urgent_help_active",
        "override_active", "override_blocks_phone_hours",
        "practice_queue_allowed", "pharmacy_transfer_allowed",
        "specialist_transfer_allowed", "opening_hours", "phone_hours",
        "spoken_information", "dtmf",
    }
    if not isinstance(value, Mapping) or set(value) != required:
        raise ProtocolError("call_policy_shape_invalid")
    if (
        value.get("protocol") != "kienzlefon-ai-call-policy-v1"
        or value.get("valid_for_ms") != 1000
        or not isinstance(value.get("evaluated_at"), str)
        or not isinstance(value.get("timezone"), str)
    ):
        raise ProtocolError("call_policy_header_invalid")
    try:
        evaluated = datetime.fromisoformat(value["evaluated_at"])
    except ValueError as exc:
        raise ProtocolError("call_policy_time_invalid") from exc
    if evaluated.tzinfo is None:
        raise ProtocolError("call_policy_time_invalid")
    boolean_fields = required - {
        "protocol", "evaluated_at", "valid_for_ms", "timezone",
        "opening_hours", "phone_hours", "spoken_information", "dtmf",
    }
    if any(not isinstance(value[name], bool) for name in boolean_fields):
        raise ProtocolError("call_policy_boolean_invalid")
    for schedule_name in ("opening_hours", "phone_hours"):
        schedule = value[schedule_name]
        if not isinstance(schedule, list) or len(schedule) != 7:
            raise ProtocolError("call_policy_schedule_invalid")
        for expected_day, day in enumerate(schedule, start=1):
            if (
                not isinstance(day, Mapping)
                or set(day) != {"weekday", "windows"}
                or day.get("weekday") != expected_day
                or not isinstance(day.get("windows"), list)
            ):
                raise ProtocolError("call_policy_schedule_invalid")
            for window in day["windows"]:
                if (
                    not isinstance(window, Mapping)
                    or set(window) != {"start", "end"}
                    or not all(
                        isinstance(window.get(name), str)
                        and re.fullmatch(r"[0-2][0-9]:[0-5][0-9]", window[name])
                        for name in ("start", "end")
                    )
                ):
                    raise ProtocolError("call_policy_schedule_invalid")
    spoken = value["spoken_information"]
    if (
        not isinstance(spoken, Mapping)
        or set(spoken) != {"opening_hours", "phone_hours"}
        or any(
            not isinstance(spoken[name], str)
            or len(spoken[name]) > SUMMARY_LIMIT
            or "\x00" in spoken[name]
            for name in ("opening_hours", "phone_hours")
        )
    ):
        raise ProtocolError("call_policy_spoken_information_invalid")
    dtmf = value["dtmf"]
    if (
        not isinstance(dtmf, Mapping)
        or set(dtmf) != {"mode", "digits"}
        or dtmf.get("mode") != "classic_handoff"
        or dtmf.get("digits") != list("0123456789*#")
    ):
        raise ProtocolError("call_policy_dtmf_invalid")
    return json.loads(json.dumps(value, ensure_ascii=False))


def build_llm_messages(
    config: AgentConfig,
    state: ConversationState,
    transcript: str,
    policy: Mapping[str, Any],
) -> list[dict[str, str]]:
    overlay = (
        config.telephone_overlay
        if state.channel == "telephone"
        else config.chat_overlay
    )
    state_summary = json.dumps(
        state_payload(state, policy),
        ensure_ascii=False,
        separators=(",", ":"),
    )

    backend_control = ""
    if state.channel == "telephone":
        backend_control = (
            "\n\nBackend-Steuerung: "
            "caller_phone_available=true bedeutet: caller_id ist bereits als "
            "Rufnummer bekannt; frage nicht danach und bestätige sie nicht. "
            "Verwende caller_id als telefon, außer der Anrufer nennt ausdrücklich "
            "eine andere Rufnummer; dann gilt die ausdrücklich genannte Nummer. "
            "Die allgemeine Abschlussfrage stellt ausschließlich das Backend; "
            "stelle sie selbst nicht."
        )
        if state.au_callback_pending:
            backend_control += (
                " Das Backend wartet auf die Antwort zur AU-Rückruffrage. Erzeuge "
                "dafür keinen Auftrag; persönliches Vorbeikommen ist kein Termin."
            )
        elif state.pending_au in {"new", "extension"}:
            backend_control += (
                " AU ist bereits vom Backend erkannt: Erzeuge dafür keinen Auftrag "
                "und keine AU-Antwort. Erfasse jedes gleichzeitig genannte andere "
                "Anliegen als eigenen Auftrag."
            )

    system_content = (
        config.system_prompt.rstrip()
        + "\n\n"
        + overlay.rstrip()
        + "\n\nAktueller bestätigter Arbeitszustand: "
        + state_summary
        + backend_control
    )
    return [
        {"role": "system", "content": system_content},
        *state.messages[-20:],
        {"role": "user", "content": transcript},
    ]


def build_llm_payload(
    config: AgentConfig,
    state: ConversationState,
    transcript: str,
    policy: Mapping[str, Any],
) -> dict[str, Any]:
    if (
        state.channel == "telephone"
        and not state.au_callback_pending
        and not state.au_handled
    ):
        au_intent = detect_au_intent(transcript)
        if au_intent:
            state.pending_au = au_intent
        elif _AU_NEGATION_RE.search(transcript):
            state.pending_au = ""

    messages = build_llm_messages(config, state, transcript, policy)

    schema = llm_schema()

    if state.channel == "telephone" and state.caller_id:
        phone_schema = (
            schema["properties"]["orders"]["items"]
            ["properties"]["fields"]["properties"]["telefon"]
        )
        phone_schema["description"] = (
            "Bekannte Rufnummer aus der Anruferkennung ist "
            f"{state.caller_id}. Verwende diese als telefon, sofern der "
            "Anrufer nicht ausdrücklich eine andere Rufnummer nennt. "
            "Eine ausdrücklich genannte andere Rufnummer hat Vorrang."
        )

    payload = {
        "model": "default",
        "messages": messages,
        "stream": False,
        "max_tokens": config.max_llm_tokens,
        "temperature": config.temperature,
        "chat_template_kwargs": {"enable_thinking": False},
        "response_format": {
            "type": "json_schema",
            "json_schema": {
                "name": "kienzlefon_dialog_turn_v1",
                "strict": True,
                "schema": schema,
            },
        },
    }
    return payload


def decode_llm_envelope(
    envelope: Any, state: ConversationState, transcript: str, policy: Mapping[str, Any]
) -> LLMResult:
    try:
        choice = envelope["choices"][0]
        content = choice["message"]["content"]
        if not isinstance(content, str):
            raise ProtocolError("llm_content_missing")
        try:
            parsed_content = json.loads(content)
        except json.JSONDecodeError as exc:
            LOGGER.error(
                "llm_content_json_invalid finish_reason=%r content_chars=%d "
                "json_error=%s pos=%d",
                choice.get("finish_reason"),
                len(content),
                exc.msg,
                exc.pos,
            )
            raise
        validated = validate_llm_result(
            parsed_content,
            state,
            policy,
        )
        validated = normalize_external_message_result(
            state,
            validated,
            transcript,
        )
        validated = normalize_au_result(
            state,
            validated,
            transcript,
            policy,
        )
        return normalize_final_check_result(
            state,
            validated,
        )
    except (KeyError, IndexError, TypeError, json.JSONDecodeError) as exc:
        raise ProtocolError("llm_response_invalid") from exc


def call_llm(
    config: AgentConfig, state: ConversationState, transcript: str,
    policy: Mapping[str, Any],
) -> LLMResult:
    payload = build_llm_payload(config, state, transcript, policy)
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
    connection, path = http_connection(config.llm_url, config.http_timeout)
    try:
        connection.request("POST", path, body=body, headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json", "Authorization": "Bearer no-key",
        })
        response = connection.getresponse()
        response_body = response.read(2 * 1024 * 1024 + 1)
        if (not 200 <= response.status < 300 or len(response_body) > 2 * 1024 * 1024
                or "application/json" not in response.getheader("Content-Type", "").lower()):
            raise ProtocolError("llm_http_failure")
        try:
            envelope = json.loads(response_body)
        except (ValueError, UnicodeError) as exc:
            raise ProtocolError("llm_response_invalid") from exc
        return decode_llm_envelope(envelope, state, transcript, policy)
    finally:
        connection.close()


async def async_llm_envelope(config: AgentConfig, payload: Mapping[str, Any]) -> Any:
    """Cancellable, bounded HTTP request; cancellation closes the real socket.

    Do not use to_thread here: cancelling its await would leave an obsolete
    inference running and competing with the final request on the server.
    """
    parsed = urlsplit(config.llm_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ProtocolError("invalid_llm_url")
    secure = parsed.scheme == "https"
    port = parsed.port or (443 if secure else 80)
    path = (parsed.path or "/") + ("?" + parsed.query if parsed.query else "")
    host = parsed.hostname
    authority = (f"[{host}]" if ":" in host else host) + f":{port}"
    if any(char in path + authority for char in "\r\n"):
        raise ProtocolError("invalid_llm_url")
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
    writer: asyncio.StreamWriter | None = None
    limit = 2 * 1024 * 1024
    try:
        async with asyncio.timeout(config.http_timeout):
            reader, writer = await asyncio.open_connection(
                host, port, ssl=ssl.create_default_context() if secure else None,
                limit=65536,
            )
            header = (
                f"POST {path} HTTP/1.1\r\nHost: {authority}\r\n"
                "Content-Type: application/json; charset=utf-8\r\n"
                "Accept: application/json\r\nAccept-Encoding: identity\r\n"
                "Authorization: Bearer no-key\r\nConnection: close\r\n"
                f"Content-Length: {len(body)}\r\n\r\n"
            ).encode("ascii")
            writer.write(header + body)
            await writer.drain()
            raw_header = await reader.readuntil(b"\r\n\r\n")
            if len(raw_header) > 32768:
                raise ProtocolError("llm_http_headers_too_large")
            lines = raw_header.decode("iso-8859-1").split("\r\n")
            status = lines[0].split()
            if len(status) < 2 or status[0] not in {"HTTP/1.0", "HTTP/1.1"}:
                raise ProtocolError("llm_http_failure")
            if not 200 <= int(status[1]) < 300:
                raise ProtocolError("llm_http_failure")
            headers: dict[str, str] = {}
            for line in lines[1:]:
                if not line:
                    continue
                name, separator, value = line.partition(":")
                name = name.lower().strip()
                if not separator or name in headers:
                    raise ProtocolError("llm_http_headers_invalid")
                headers[name] = value.strip()
            if "application/json" not in headers.get("content-type", "").lower():
                raise ProtocolError("llm_http_failure")
            if headers.get("content-encoding", "identity").lower() != "identity":
                raise ProtocolError("llm_http_encoding_invalid")
            output = bytearray()
            transfer = headers.get("transfer-encoding", "").lower()
            if transfer:
                if transfer != "chunked" or "content-length" in headers:
                    raise ProtocolError("llm_http_framing_invalid")
                while True:
                    line = await reader.readuntil(b"\r\n")
                    if len(line) > 4096:
                        raise ProtocolError("llm_http_framing_invalid")
                    size = int(line.split(b";", 1)[0].strip(), 16)
                    if size < 0 or len(output) + size > limit:
                        raise ProtocolError("llm_response_too_large")
                    if size == 0:
                        break
                    output.extend(await reader.readexactly(size))
                    if await reader.readexactly(2) != b"\r\n":
                        raise ProtocolError("llm_http_framing_invalid")
            elif "content-length" in headers:
                size = int(headers["content-length"])
                if size < 0 or size > limit:
                    raise ProtocolError("llm_response_too_large")
                output.extend(await reader.readexactly(size))
            else:
                while chunk := await reader.read(min(65536, limit + 1 - len(output))):
                    output.extend(chunk)
                    if len(output) > limit:
                        raise ProtocolError("llm_response_too_large")
            return json.loads(output)
    except TimeoutError as exc:
        raise ProtocolError("llm_timeout") from exc
    except (ValueError, UnicodeError, asyncio.IncompleteReadError, asyncio.LimitOverrunError) as exc:
        raise ProtocolError("llm_response_invalid") from exc
    finally:
        if writer is not None:
            writer.close()
            with contextlib.suppress(Exception):
                await asyncio.wait_for(writer.wait_closed(), 1.0)


def llm_policy_key(policy: Mapping[str, Any]) -> str:
    # evaluated_at is refreshed by the admission service on every request.
    # All decision-bearing fields, schedules and spoken information must match.
    return json.dumps({key: value for key, value in policy.items() if key != "evaluated_at"},
                      sort_keys=True, ensure_ascii=False, separators=(",", ":"))


@dataclass
class LLMCandidate:
    transcript: str
    speculative: bool
    policy: dict[str, Any] = field(default_factory=dict)
    task: asyncio.Task[None] | None = None
    envelope: Any = None
    error: str = ""
    started_ns: int | None = None
    finished_ns: int | None = None


class SpeculativeLLMTurn:
    """One isolated turn, latest text wins; no speech/commit/history side effects."""

    STABLE_SECONDS = 0.30
    MIN_START_INTERVAL_SECONDS = 0.75
    MAX_SPECULATIVE_REQUESTS = 3

    def __init__(self, config: AgentConfig, state: ConversationState,
                 get_policy: Callable[[], Any], slot_index: int = 0) -> None:
        if not 0 <= slot_index < 3:
            raise AgentError("invalid_llm_slot")
        self.config = config
        self.slot_index = slot_index
        self.snapshot = copy.deepcopy(state)
        self.get_policy = get_policy
        self.latest = ""
        self.changed_at = 0.0
        self.last_launch = 0.0
        self.changed = asyncio.Event()
        self.accepting = True
        self.current: LLMCandidate | None = None
        self.tasks: set[asyncio.Task[None]] = set()
        self.requests = self.discarded = self.failures = self.reused = 0
        self.first_started_ns: int | None = None
        self.selected_started_ns: int | None = None
        self.selected_duration_ms: int | None = None
        self.manager = asyncio.create_task(self._manage(), name="llm-speculation-manager")

    def offer(self, transcript: str) -> None:
        if not self.accepting:
            return
        value = transcript.strip()
        if len(value) > TRANSCRIPT_LIMIT or "\x00" in value:
            value = ""
        if value != self.latest:
            self.latest = value
            self.changed_at = time.monotonic()
            self.changed.set()

    async def _request(self, candidate: LLMCandidate) -> None:
        try:
            if not candidate.policy:
                candidate.policy = dict(await self.get_policy())
            working = copy.deepcopy(self.snapshot)
            payload = build_llm_payload(self.config, working, candidate.transcript, candidate.policy)
            payload["cache_prompt"] = True  # RAM prefix reuse, no disk cache.
            # Replacements queue for the same llama.cpp slot. Its disconnect
            # cancellation may lag; never spill an obsolete turn into another slot.
            payload["id_slot"] = self.slot_index
            candidate.started_ns = time.monotonic_ns()
            if candidate.speculative and self.first_started_ns is None:
                self.first_started_ns = candidate.started_ns
            candidate.envelope = await async_llm_envelope(self.config, payload)
        except Exception as error:
            candidate.error = diagnostic_error_code(error)
            if candidate.speculative:
                self.failures += 1
        finally:
            candidate.finished_ns = time.monotonic_ns()

    def _launch(self, transcript: str, speculative: bool,
                policy: Mapping[str, Any] | None = None) -> LLMCandidate:
        candidate = LLMCandidate(transcript, speculative, dict(policy or {}))
        self.current = candidate
        self.last_launch = time.monotonic()
        if speculative:
            self.requests += 1
        candidate.task = asyncio.create_task(self._request(candidate), name="llm-candidate")
        self.tasks.add(candidate.task)
        candidate.task.add_done_callback(self.tasks.discard)
        return candidate

    async def _discard(self) -> None:
        candidate, self.current = self.current, None
        if candidate is not None:
            if candidate.speculative:
                self.discarded += 1
            if candidate.task is not None:
                candidate.task.cancel()
                await asyncio.gather(candidate.task, return_exceptions=True)

    async def _manage(self) -> None:
        while True:
            self.changed.clear()
            if self.current is not None and self.current.transcript != self.latest:
                await self._discard()
            if (self.current is None and len(self.latest) >= 2
                    and self.requests < self.MAX_SPECULATIVE_REQUESTS):
                wait = max(self.changed_at + self.STABLE_SECONDS,
                           self.last_launch + self.MIN_START_INTERVAL_SECONDS) - time.monotonic()
                if wait > 0:
                    try:
                        await asyncio.wait_for(self.changed.wait(), wait)
                    except TimeoutError:
                        pass
                    continue
                self._launch(self.latest, True)
            await self.changed.wait()

    async def freeze(self) -> None:
        self.accepting = False
        self.manager.cancel()
        await asyncio.gather(self.manager, return_exceptions=True)

    async def finish(self, transcript: str, state: ConversationState) -> tuple[LLMResult, ConversationState]:
        await self.freeze()
        if state != self.snapshot:
            await self._discard()
            self.snapshot = copy.deepcopy(state)
        # Refresh permissions both before reusing a hypothesis and before release.
        # A changed policy gets one fresh retry, not an unbounded request loop.
        policy = dict(await self.get_policy())
        for attempt in range(2):
            candidate = self.current
            if (candidate is not None and (candidate.transcript != transcript
                    or not candidate.policy or llm_policy_key(candidate.policy) != llm_policy_key(policy)
                    or candidate.error)):
                await self._discard()
                candidate = None
            if candidate is None:
                candidate = self._launch(transcript, False, policy)
            assert candidate.task is not None
            await candidate.task
            if candidate.error:
                if candidate.speculative:
                    await self._discard()
                    candidate = self._launch(transcript, False, policy)
                    assert candidate.task is not None
                    await candidate.task
                if candidate.error:
                    raise ProtocolError(candidate.error)
            current_policy = dict(await self.get_policy())
            if llm_policy_key(current_policy) != llm_policy_key(policy):
                await self._discard()
                policy = current_policy
                continue
            working = copy.deepcopy(state)
            # Apply transcript-derived state only to the accepted final snapshot.
            build_llm_payload(self.config, working, transcript, current_policy)
            try:
                result = decode_llm_envelope(candidate.envelope, working, transcript, current_policy)
            except (AgentError, ValueError, TypeError):
                if candidate.speculative and attempt == 0:
                    self.failures += 1
                    await self._discard()
                    policy = current_policy
                    continue
                raise
            self.reused = int(candidate.speculative)
            self.selected_started_ns = candidate.started_ns
            if candidate.started_ns is not None and candidate.finished_ns is not None:
                self.selected_duration_ms = round((candidate.finished_ns - candidate.started_ns) / 1_000_000)
            return result, working
        raise ProtocolError("llm_policy_changed")

    def update_metrics(self, metrics: TurnPerformance) -> None:
        metrics.llm_speculative_requests = self.requests
        metrics.llm_speculative_discarded = self.discarded
        metrics.llm_speculative_failures = self.failures
        metrics.llm_speculative_reused = self.reused
        endpoint = metrics.utterance.endpoint_detected_monotonic_ns
        if self.first_started_ns is not None:
            metrics.llm_speculative_lead_ms = max(0, round((endpoint - self.first_started_ns) / 1_000_000))
        if self.selected_started_ns is not None:
            metrics.end_of_detected_speech_to_llm_start_ms = round((self.selected_started_ns - endpoint) / 1_000_000)
        if self.selected_duration_ms is not None:
            metrics.llm_ms = self.selected_duration_ms

    async def close(self) -> None:
        await self.freeze()
        tasks = list(self.tasks)
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        self.current = None
        self.latest = ""
        self.snapshot = ConversationState(channel="telephone")


def _validate_audio_headers(
    response: http.client.HTTPResponse,
    expected_rate: int,
    require_explicit_format: bool,
) -> int:
    content_type = response.getheader("Content-Type", "").lower()
    if "audio/pcm" not in content_type and "application/octet-stream" not in content_type:
        raise ProtocolError("tts_content_type_invalid")
    rate_header = response.getheader("X-Sample-Rate")
    if rate_header:
        if not rate_header.isdigit():
            raise ProtocolError("tts_sample_rate_invalid")
        rate = int(rate_header)
    elif not require_explicit_format:
        rate = expected_rate
    else:
        raise ProtocolError("tts_sample_rate_missing")
    if rate != expected_rate:
        raise ProtocolError("tts_sample_rate_unexpected")
    channels = response.getheader("X-Channels")
    if channels is None and require_explicit_format:
        raise ProtocolError("tts_channels_missing")
    if channels is not None and channels != "1":
        raise ProtocolError("tts_channels_invalid")
    sample_format = response.getheader("X-Sample-Format")
    if sample_format is None and require_explicit_format:
        raise ProtocolError("tts_sample_format_missing")
    if sample_format is not None and sample_format.lower() not in {"s16le", "pcm_s16le"}:
        raise ProtocolError("tts_sample_format_invalid")
    return rate


def stream_tts(
    config: AgentConfig,
    text: str,
    backend: str,
    emit: Callable[[bytes], None],
    debug: Callable[[str, Mapping[str, Any]], None] | None = None,
) -> None:
    if not text or len(text) > REPLY_LIMIT or "\x00" in text:
        raise ProtocolError("tts_input_invalid")
    if backend == "qwen":
        url = config.qwen_url
        payload = {
            "text": text,
            "speaker": config.qwen_speaker,
            "language": config.qwen_language,
            "seed": config.qwen_seed,
        }
        expected_rate = 24000
        require_explicit_format = True
    elif backend == "piper":
        url = config.piper_url
        payload = {"input": text, "response_format": "pcm"}
        expected_rate = 22050
        require_explicit_format = False
    else:
        raise ProtocolError("tts_backend_invalid")
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
    connection, path = http_connection(url, config.http_timeout)
    resampler: BandlimitedPCMResampler | None = None
    received = 0
    header_checked = False
    header_probe = bytearray()
    try:
        connection.request(
            "POST",
            path,
            body=body,
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "Accept": "audio/pcm, application/octet-stream",
            },
        )
        response = connection.getresponse()
        if not 200 <= response.status < 300:
            response.read(4096)
            raise ProtocolError("tts_http_failure")
        rate = _validate_audio_headers(response, expected_rate, require_explicit_format)
        resampler = BandlimitedPCMResampler(rate, TELEPHONY_RATE)
        if debug is not None:
            debug("tts_media_format", {
                "backend": backend,
                "source_encoding": "pcm_s16le",
                "source_rate": rate,
                "target_encoding": "pcm_s16le",
                "target_rate": TELEPHONY_RATE,
                "audiosocket_format": TELEPHONY_FORMAT,
                "audiosocket_type": f"0x{AUDIO_TYPE_SLIN16:02x}",
                "frame_ms": FRAME_MS,
                "frame_bytes": TELEPHONY_FRAME_BYTES,
                "resampler": "windowed_sinc_blackman_32tap",
            })
        read_method = getattr(response, "read1", response.read)
        while True:
            block = read_method(8192)
            if not block:
                break
            if not header_checked:
                header_probe.extend(block)
                if len(header_probe) < 12:
                    continue
                if header_probe[:4] == b"RIFF" and header_probe[8:12] == b"WAVE":
                    raise ProtocolError("tts_returned_wav")
                block = bytes(header_probe)
                header_probe.clear()
                header_checked = True
            converted = resampler.feed(block)
            if converted:
                received += len(converted)
                emit(converted)
        if header_probe:
            converted = resampler.feed(bytes(header_probe))
            if converted:
                received += len(converted)
                emit(converted)
        if resampler.remainder:
            raise ProtocolError("tts_pcm_alignment_invalid")
        tail = resampler.feed(b"", final=True)
        if tail:
            received += len(tail)
            emit(tail)
        if not received:
            raise ProtocolError("tts_empty_audio")
    finally:
        connection.close()


def commit_order(
    config: AgentConfig,
    request_id: str,
    caller_id: str,
    order: OrderState,
) -> str:
    commit_request_id = "ai-order-" + hashlib.sha256(
        f"{request_id}:{order.order_id}".encode()
    ).hexdigest()[:48]
    payload = {
        "request_id": commit_request_id,
        "caller_id": caller_id,
        "call_type": order.call_type,
        "fields": dict(order.fields),
        "zusammenfassung": order.zusammenfassung,
    }
    result = subprocess.run(
        [
            str(config.kienzlefon_python),
            str(Path(__file__).resolve()),
            "commit-helper",
            "--config",
            str(config.source),
        ],
        input=json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        text=True,
        capture_output=True,
        timeout=60,
        check=False,
    )
    if result.returncode != 0:
        raise AgentError("commit_helper_failed")
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise AgentError("commit_helper_invalid_response") from exc
    call_id = str(response.get("call_id", ""))
    if response.get("committed") is not True or not IDENTIFIER_RE.fullmatch(call_id):
        raise AgentError("commit_not_confirmed")
    return call_id


def _write_json_atomic(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp.{os.getpid()}.{os.urandom(4).hex()}")
    try:
        with temporary.open("x", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o640)
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        temporary.unlink(missing_ok=True)


def commit_helper(config: AgentConfig) -> int:
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, Mapping):
            raise ProtocolError("commit_payload_invalid")
        request_id = _safe_identifier(payload.get("request_id"), "request_id")
        caller_id = _safe_caller(payload.get("caller_id")) or None
        call_type_name = str(payload.get("call_type", ""))
        values = payload.get("fields")
        summary = payload.get("zusammenfassung")
        if call_type_name not in ALLOWED_CALL_TYPES or not isinstance(values, Mapping):
            raise ProtocolError("commit_fields_invalid")
        if (
            not isinstance(summary, str)
            or not summary.strip()
            or len(summary) > SUMMARY_LIMIT
            or "\x00" in summary
        ):
            raise ProtocolError("commit_summary_invalid")
        summary = summary.strip()
        clean_values: dict[str, str] = {}
        for name in ALL_FIELDS:
            value = values.get(name, "")
            if not isinstance(value, str) or len(value) > FIELD_LIMIT or "\x00" in value:
                raise ProtocolError("commit_field_value_invalid")
            clean_values[name] = value.strip()
            if (
                name == "telefon"
                and clean_values[name]
                and not PHONE_RE.fullmatch(clean_values[name])
            ):
                raise ProtocolError("commit_phone_value_invalid")
        missing = [name for name in ALLOWED_CALL_TYPES[call_type_name] if not clean_values[name]]
        if missing:
            raise ProtocolError("commit_missing_required_fields")

        from kienzlefon.config import load_config as load_kienzlefon_config
        from kienzlefon.models import AudioStatus, CallState, CallType, FieldName
        from kienzlefon.spool import SUMMARY_UNAVAILABLE, Spool, WorkingCall
        from kienzlefon.worker import Worker

        kconfig = load_kienzlefon_config(config.kienzlefon_config)
        spool = Spool(kconfig.paths.spool, kconfig.practice.timezone)
        spool.initialize()
        ledger_dir = config.state_directory / "commits"
        ledger_dir.mkdir(parents=True, exist_ok=True)
        lock_path = config.state_directory / "commit.lock"
        digest = hashlib.sha256(request_id.encode()).hexdigest()
        payload_digest = hashlib.sha256(
            json.dumps(
                {
                    "caller_id": caller_id,
                    "call_type": call_type_name,
                    "fields": clean_values,
                    "zusammenfassung": summary,
                },
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode()
        ).hexdigest()
        ledger_path = ledger_dir / f"{digest}.json"

        with lock_path.open("a+b") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            ledger: dict[str, Any] | None = None
            if ledger_path.is_file():
                ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
                if ledger.get("request_sha256") != digest:
                    raise ProtocolError("commit_ledger_mismatch")
                if ledger.get("payload_sha256") != payload_digest:
                    raise ProtocolError("commit_payload_mismatch")
                if ledger.get("state") == "committed":
                    print(json.dumps({"committed": True, "call_id": ledger["call_id"]}))
                    return 0

            call: WorkingCall
            if ledger is None:
                call_type = CallType(call_type_name)
                category = {
                    "rezeptbestellung": "rezept",
                    "ueb_req": "ueberweisung",
                    "termin": "termin",
                    "rueckruf_details": "rueckruf",
                    "rueckruf_tel_grund": "rueckruf",
                    "sonstiges": "sonstiges",
                }[call_type_name]
                call = spool.create_call(call_type, caller_id, category)
                ledger = {
                    "version": 1,
                    "request_sha256": digest,
                    "payload_sha256": payload_digest,
                    "call_id": call.call_id,
                    "state": "started",
                }
                _write_json_atomic(ledger_path, ledger)
            else:
                call_id = str(ledger.get("call_id", ""))
                matches = [
                    kconfig.paths.spool / state.value / call_id
                    for state in CallState
                    if (kconfig.paths.spool / state.value / call_id).is_dir()
                ]
                if len(matches) != 1:
                    raise ProtocolError("commit_recovery_ambiguous")
                call = WorkingCall(matches[0], kconfig.practice.timezone)

            if call.path.parent.name == CallState.READY.value:
                ledger["state"] = "committed"
                _write_json_atomic(ledger_path, ledger)
                print(json.dumps({"committed": True, "call_id": call.call_id}))
                return 0
            if call.path.parent.name == CallState.ERROR.value:
                raise ProtocolError("commit_call_in_error")

            record = call.load()
            if str(record.get("typ", "")) != call_type_name:
                raise ProtocolError("commit_call_type_mismatch")
            audio_entries = record.get("_kienzlefon", {}).get("audio")
            if not isinstance(audio_entries, list):
                raise ProtocolError("commit_audio_entries_invalid")
            existing_entries = {
                str(entry.get("feld", "")): entry
                for entry in audio_entries
                if isinstance(entry, Mapping)
            }
            if len(existing_entries) != len(audio_entries):
                raise ProtocolError("commit_audio_entries_ambiguous")
            changed = False
            existing_summary = record.get("zusammenfassung")
            if existing_summary is None or existing_summary == SUMMARY_UNAVAILABLE:
                record["zusammenfassung"] = summary
                changed = True
            elif str(existing_summary).strip() != summary:
                raise ProtocolError("commit_existing_summary_mismatch")
            for index, name in enumerate(ALL_FIELDS, start=1):
                text = clean_values[name]
                if not text:
                    continue
                existing = existing_entries.get(name)
                if existing is not None:
                    if (
                        existing.get("status") != AudioStatus.TRANSCRIBED.value
                        or str(existing.get("transkript", "")).strip() != text
                        or existing.get("transkribieren") is not False
                    ):
                        raise ProtocolError("commit_existing_field_mismatch")
                    continue
                filename = f"ai-{index:02d}.wav"
                audio_entries.append(
                    {
                        "feld": name,
                        "datei": f"audio/{filename}",
                        "status": AudioStatus.TRANSCRIBED.value,
                        "transkript": text,
                        "versuche": 0,
                        "transkribieren": False,
                        **({"index": 1} if name == FieldName.MEDICATION.value else {}),
                    }
                )
                changed = True
            if changed:
                call.save(record)
            if call.path.parent.name != CallState.PROCESSING.value:
                call = spool.transition(call, CallState.PROCESSING)

            class NoTranscriber:
                def transcribe(self, *_args: Any, **_kwargs: Any) -> str:
                    raise RuntimeError("AI pretranscribed commit attempted local ASR")

            class NoHeartbeat:
                def set_ready(self, *_args: Any, **_kwargs: Any) -> None:
                    return None

            worker = Worker(kconfig, transcriber=NoTranscriber())
            worker.heartbeat = NoHeartbeat()
            worker.process(call)
            ready = kconfig.paths.spool / CallState.READY.value / call.call_id
            if not ready.is_dir():
                raise ProtocolError("commit_output_not_ready")
            ledger["state"] = "committed"
            _write_json_atomic(ledger_path, ledger)
            print(json.dumps({"committed": True, "call_id": call.call_id}))
            return 0
    except Exception:
        print(json.dumps({"committed": False, "error": "commit_failed"}))
        return 1


async def read_audiosocket_frame(reader: asyncio.StreamReader) -> tuple[int, bytes]:
    header = await reader.readexactly(3)
    kind = header[0]
    length = struct.unpack("!H", header[1:])[0]
    payload = await reader.readexactly(length) if length else b""
    return kind, payload


async def write_audiosocket_frame(
    writer: asyncio.StreamWriter, lock: asyncio.Lock, kind: int, payload: bytes = b""
) -> None:
    if len(payload) > 65535:
        raise ProtocolError("audiosocket_frame_too_large")
    async with lock:
        writer.write(bytes([kind]) + struct.pack("!H", len(payload)) + payload)
        await writer.drain()


FILLER_DIRECTORY = Path("/opt/kienzlefon-ai-asterisk-backend/audio/filler-v1")
FILLER_TEXTS = ("Bitte warten.", "Ich verarbeite.", "Bitte warten.")
FILLER_FILES = ("01-bitte-warten.pcm", "02-ich-verarbeite.pcm", "03-bitte-warten.pcm")
FILLER_MAX_BYTES = TELEPHONY_RATE * PCM_WIDTH * 10  # at most 10 seconds per clip


def filler_options(raw: Mapping[str, Any]) -> dict[str, Any]:
    """Strict, content-free validation shared by all runtime/maintenance commands."""
    if not isinstance(raw, Mapping):
        raise AgentError("invalid_filler_section")
    def integer(key: str, default: int, low: int, high: int) -> int:
        value = raw.get(key, default)
        if type(value) is not int or not low <= value <= high:
            raise AgentError("invalid_filler_" + key)
        return value
    def switch(key: str, default: bool) -> bool:
        value = raw.get(key, default)
        if type(value) is not bool:
            raise AgentError("invalid_filler_" + key)
        return value
    texts = tuple(raw.get(f"part{i}_text", text) for i, text in enumerate(FILLER_TEXTS, 1))
    if any(not isinstance(text, str) or len(text) > 240
           or any(ord(char) < 32 or ord(char) == 127 for char in text) for text in texts):
        raise AgentError("invalid_filler_text")
    texts = tuple(text.strip() for text in texts)
    starts = tuple(integer(f"part{i}_start_ms", default, 0, 120000)
                   for i, default in enumerate((2000, 7000, 13000), 1))
    active_starts = [start for text, start in zip(texts, starts) if text]
    if active_starts != sorted(active_starts):
        raise AgentError("invalid_filler_start_order")
    interval = integer("beep_interval_ms", 1000, 200, 10000)
    duration = integer("beep_duration_ms", 100, 20, 500)
    if duration > interval or duration % FRAME_MS:
        raise AgentError("invalid_filler_beep_duration_ms")
    volume = raw.get("beep_volume", 0.15)
    if type(volume) not in (int, float) or not math.isfinite(volume) or not 0 <= volume <= 0.5:
        raise AgentError("invalid_filler_beep_volume")
    return {
        "filler_texts": texts, "filler_start_ms": starts,
        "filler_regenerate_on_reload": switch("regenerate_on_reload", True),
        "filler_beep_enabled": switch("beep_enabled", True),
        "filler_beep_start_ms": integer("beep_start_ms", 0, 0, 120000),
        "filler_beep_interval_ms": interval,
        "filler_beep_frequency_hz": integer("beep_frequency_hz", 400, 200, 2000),
        "filler_beep_duration_ms": duration, "filler_beep_volume": float(volume),
    }


def filler_texts(config: AgentConfig) -> tuple[str, ...]:
    return getattr(config, "filler_texts", FILLER_TEXTS)


def filler_profile(config: AgentConfig) -> str:
    # Legacy whole-set profile, retained solely to import the selected 2.4.x clips.
    value = ["filler-v1", TELEPHONY_RATE, config.qwen_speaker,
             config.qwen_language, config.filler_seed, FILLER_TEXTS]
    return hashlib.sha256(json.dumps(value, ensure_ascii=False).encode()).hexdigest()


def filler_clip_profile(config: AgentConfig, text: str) -> str:
    value = ["filler-clip-v2", TELEPHONY_RATE, config.qwen_speaker,
             config.qwen_language, config.filler_seed, text]
    return hashlib.sha256(json.dumps(value, ensure_ascii=False).encode()).hexdigest()


def read_filler_manifest(directory: Path) -> Mapping[str, Any]:
    path = directory / "manifest.json"
    if (directory.is_symlink() or path.is_symlink() or not path.is_file()
            or path.stat().st_size > 16384):
        raise ProtocolError("filler_manifest_invalid")
    manifest = json.loads(path.read_text(encoding="ascii"))
    if (not isinstance(manifest, dict) or manifest.get("sample_rate") != TELEPHONY_RATE
            or manifest.get("encoding") != "pcm_s16le" or manifest.get("channels") != 1
            or not isinstance(manifest.get("clips"), dict)
            or set(manifest["clips"]) != set(FILLER_FILES)):
        raise ProtocolError("filler_manifest_invalid")
    return manifest


def read_filler_pcm(directory: Path, name: str, expected_hash: str) -> bytes:
    path = directory / name
    if (path.is_symlink() or not path.is_file()
            or not TELEPHONY_FRAME_BYTES <= path.stat().st_size <= FILLER_MAX_BYTES):
        raise ProtocolError("filler_clip_invalid")
    pcm = path.read_bytes()
    if (len(pcm) % TELEPHONY_FRAME_BYTES or not any(pcm)
            or hashlib.sha256(pcm).hexdigest() != expected_hash):
        raise ProtocolError("filler_clip_invalid")
    return pcm


def load_filler_clips(config: AgentConfig, directory: Path = FILLER_DIRECTORY) -> tuple[bytes, ...]:
    texts = filler_texts(config)
    if not any(texts):
        return (b"", b"", b"")
    manifest = read_filler_manifest(directory)
    legacy = manifest.get("schema_version") is None
    if legacy and (manifest.get("profile") != filler_profile(config) or texts != FILLER_TEXTS):
        raise ProtocolError("filler_profile_mismatch")
    if not legacy and manifest.get("schema_version") != 2:
        raise ProtocolError("filler_manifest_invalid")
    clips = []
    for name, text in zip(FILLER_FILES, texts):
        if not text:
            clips.append(b"")
            continue
        entry = manifest["clips"][name]
        if not legacy and (not isinstance(entry, dict)
                           or entry.get("profile") != filler_clip_profile(config, text)):
            raise ProtocolError("filler_profile_mismatch")
        clips.append(read_filler_pcm(directory, name, entry if legacy else entry.get("sha256")))
    return tuple(clips)


def prepare_filler_clips(config: AgentConfig, directory: Path,
                         reuse: Path = FILLER_DIRECTORY) -> None:
    """Explicit idle maintenance only; stage a complete set without changing reuse."""
    cached: dict[str, bytes] = {}
    try:
        manifest = read_filler_manifest(reuse)
    except (OSError, ValueError, AgentError):
        manifest = {}
    legacy = manifest.get("schema_version") is None and manifest.get("profile") == filler_profile(config)
    for name, legacy_text in zip(FILLER_FILES, FILLER_TEXTS):
        entry = manifest.get("clips", {}).get(name)
        try:
            if legacy and isinstance(entry, str):
                cached[filler_clip_profile(config, legacy_text)] = read_filler_pcm(reuse, name, entry)
            elif manifest.get("schema_version") == 2 and isinstance(entry, dict):
                profile = entry.get("profile")
                if isinstance(profile, str) and re.fullmatch(r"[0-9a-f]{64}", profile):
                    cached[profile] = read_filler_pcm(reuse, name, entry.get("sha256"))
        except (OSError, ValueError, AgentError):
            pass  # A broken part must not force regeneration of all other parts.
    clips = []
    generated = 0
    for text in filler_texts(config):
        if not text:
            clips.append(b"")
            continue
        profile = filler_clip_profile(config, text)
        if profile not in cached:
            pcm = bytearray()

            def collect(block: bytes) -> None:
                if len(pcm) + len(block) > FILLER_MAX_BYTES:
                    raise ProtocolError("filler_clip_too_long")
                pcm.extend(block)

            # Existing resident Qwen API, no fallback model, no service changes.
            stream_tts(replace(config, qwen_seed=config.filler_seed), text, "qwen", collect)
            if not pcm or len(pcm) % PCM_WIDTH or not any(pcm):
                raise ProtocolError("filler_clip_invalid")
            pcm.extend(b"\0" * (-len(pcm) % TELEPHONY_FRAME_BYTES))
            cached[profile] = bytes(pcm)
            generated += 1
        clips.append(cached[profile])
    directory.mkdir(parents=True, exist_ok=True)
    if directory.is_symlink():
        raise ProtocolError("filler_directory_invalid")
    manifest = {"schema_version": 2, "sample_rate": TELEPHONY_RATE,
                "encoding": "pcm_s16le", "channels": 1, "seed": config.filler_seed,
                "clips": {}}
    for name, text, pcm in zip(FILLER_FILES, filler_texts(config), clips):
        path = directory / name
        if path.is_symlink():
            raise ProtocolError("filler_clip_invalid")
        path.write_bytes(pcm)
        path.chmod(0o644)
        manifest["clips"][name] = {"profile": filler_clip_profile(config, text),
                                   "sha256": hashlib.sha256(pcm).hexdigest()}
    manifest_path = directory / "manifest.json"
    if manifest_path.is_symlink():
        raise ProtocolError("filler_manifest_invalid")
    manifest_path.write_text(json.dumps(manifest, sort_keys=True) + "\n", encoding="ascii")
    manifest_path.chmod(0o644)
    load_filler_clips(config, directory)
    print(f"filler clips: generated={generated} enabled_parts={sum(bool(text) for text in filler_texts(config))}")


def make_filler_beep(config: AgentConfig) -> bytes:
    """Generate once per agent, without TTS/GPU; five-ms ramps prevent clicks."""
    if not getattr(config, "filler_beep_enabled", False) or config.filler_beep_volume == 0:
        return b""
    count = TELEPHONY_RATE * config.filler_beep_duration_ms // 1000
    ramp = TELEPHONY_RATE * 5 // 1000
    values = [round(32767 * config.filler_beep_volume * min(1.0, i / ramp, (count - 1 - i) / ramp)
                    * math.sin(2 * math.pi * config.filler_beep_frequency_hz * i / TELEPHONY_RATE))
              for i in range(count)]
    return struct.pack("<" + "h" * count, *values)


class FillerPlayback:
    """Absolute endpoint-relative schedule; speech and tones never overlap."""

    GAP_SECONDS = 1.0

    def __init__(self, clips: tuple[bytes, ...], writer: Any, lock: asyncio.Lock,
                 audio_active: asyncio.Event, metrics: TurnPerformance,
                 config: AgentConfig | None = None, beep: bytes = b"") -> None:
        self.clips, self.writer, self.lock = clips, writer, lock
        self.audio_active, self.metrics = audio_active, metrics
        # The no-config form is retained for isolated legacy helper tests only.
        if config is None:
            offsets = [0.0]
            for pcm in clips[:-1]:
                offsets.append(offsets[-1] + len(pcm) / (TELEPHONY_RATE * PCM_WIDTH) + self.GAP_SECONDS)
            self.starts = offsets
        else:
            self.starts = [value / 1000 for value in getattr(config, "filler_start_ms", (2000, 7000, 13000))]
        self.beep = beep
        self.beep_start = getattr(config, "filler_beep_start_ms", 0) / 1000
        self.beep_interval = getattr(config, "filler_beep_interval_ms", 1000) / 1000
        self.ready = asyncio.Event()
        self.task = asyncio.create_task(self._play(), name="static-filler-playback")

    async def _audio(self, pcm: bytes, tone: bool) -> None:
        loop = asyncio.get_running_loop()
        self.audio_active.set()
        try:
            if tone:
                self.metrics.beep_count += 1
            else:
                self.metrics.filler_blocks_started += 1
            deadline = loop.time()
            for offset in range(0, len(pcm), TELEPHONY_FRAME_BYTES):
                await write_audiosocket_frame(self.writer, self.lock, AUDIO_TYPE_SLIN16,
                                             pcm[offset:offset + TELEPHONY_FRAME_BYTES])
                kind = "beep" if tone else "filler"
                detected_key = f"end_of_detected_speech_to_first_{kind}_audio_ms"
                actual_key = f"end_of_actual_speech_to_first_{kind}_audio_ms"
                if getattr(self.metrics, detected_key) is None:
                    now = time.monotonic_ns()
                    utterance = self.metrics.utterance
                    setattr(self.metrics, detected_key, round((now - utterance.endpoint_detected_monotonic_ns) / 1_000_000))
                    setattr(self.metrics, actual_key, round((now - utterance.actual_speech_end_monotonic_ns) / 1_000_000))
                if tone:
                    self.metrics.beep_audio_ms += FRAME_MS
                else:
                    self.metrics.filler_audio_ms += FRAME_MS
                # Never burst delayed frames: bounded drift is preferable to accelerated audio.
                deadline = max(deadline, loop.time()) + FRAME_MS / 1000
                await asyncio.sleep(max(0, deadline - loop.time()))
            if not tone:
                self.metrics.filler_blocks_completed += 1
        finally:
            self.audio_active.clear()

    async def _play(self) -> None:
        loop = asyncio.get_running_loop()
        origin = loop.time() - max(0, (time.monotonic_ns() - self.metrics.utterance.endpoint_detected_monotonic_ns) / 1e9)
        parts = [(start, pcm) for start, pcm in zip(self.starts, self.clips) if pcm]
        next_part = 0
        next_beep = self.beep_start
        while not self.ready.is_set():
            now = loop.time() - origin
            speech_at = parts[next_part][0] if next_part < len(parts) else math.inf
            if speech_at <= now:
                await self._audio(parts[next_part][1], False)
                next_part += 1
                # Tones missed during a phrase are skipped, never caught up in a burst.
                now = loop.time() - origin
                next_beep = max(next_beep, self.beep_start + max(0, math.ceil((now - self.beep_start) / self.beep_interval)) * self.beep_interval)
                continue
            beep_at = next_beep if self.beep else math.inf
            if beep_at <= now:
                if now + len(self.beep) / (TELEPHONY_RATE * PCM_WIDTH) <= speech_at:
                    await self._audio(self.beep, True)
                now = loop.time() - origin
                next_beep = self.beep_start + max(1, math.floor((now - self.beep_start) / self.beep_interval) + 1) * self.beep_interval
                continue
            deadline = min(speech_at, beep_at)
            if math.isinf(deadline):
                return
            try:
                await asyncio.wait_for(self.ready.wait(), max(0, deadline - now))
            except TimeoutError:
                pass

    async def release_to_reply(self) -> None:
        started = time.monotonic_ns()
        self.ready.set()
        await self.task  # finish only the current block; skip remaining gaps/blocks
        self.metrics.reply_audio_wait_for_filler_ms = round((time.monotonic_ns() - started) / 1_000_000)

    async def close(self) -> None:
        self.ready.set()
        self.task.cancel()
        await asyncio.gather(self.task, return_exceptions=True)


class AgentServer:
    def __init__(self, config: AgentConfig, slot_index: int) -> None:
        if not 0 <= slot_index < config.slot_count:
            raise AgentError("invalid_slot_index")
        self.config = config
        self.slot_index = slot_index
        self.pending: dict[str, Claim] = {}
        self.active_uuid: str | None = None
        self.lock = asyncio.Lock()
        self.stopping = asyncio.Event()
        self.sip_registered = False
        self.publisher_reachable = False
        self.expired_claim_pending = False
        self.debug_subscribers: dict[int, DebugSubscriber] = {}
        self.debug_next_subscriber = 1
        self.debug_sequence = 0
        self.call_sequence = 0
        self.filler_clips: tuple[bytes, ...] = ()
        self.filler_beep = b""
        if getattr(config, "filler_enabled", False):
            self.filler_beep = make_filler_beep(config)
            try:
                self.filler_clips = load_filler_clips(config)
            except (OSError, ValueError, AgentError):
                LOGGER.warning("event=filler_unavailable action=continue_without_filler")
        self.performance = PerformanceWriter(
            config.performance_enabled,
            config.performance_log_file,
            config.performance_max_bytes,
            config.performance_backup_count,
        )

    def record_turn_performance(
        self,
        metrics: TurnPerformance,
        outcome: str,
        failure_stage: str = "",
        error_code: str = "",
    ) -> None:
        if not IDENTIFIER_RE.fullmatch(outcome):
            raise AgentError("performance_outcome_invalid")
        if failure_stage and not IDENTIFIER_RE.fullmatch(failure_stage):
            raise AgentError("performance_failure_stage_invalid")
        if error_code and not IDENTIFIER_RE.fullmatch(error_code):
            error_code = "internal_error"
        utterance = metrics.utterance
        record: dict[str, Any] = {
            "schema": PERFORMANCE_SCHEMA,
            "schema_version": 1,
            "program_version": VERSION,
            "recorded_at": datetime.now().astimezone().isoformat(
                timespec="milliseconds"
            ),
            "epoch_ms": time.time_ns() // 1_000_000,
            "slot_id": self.config.slot_id(self.slot_index),
            "call_sequence": self.call_sequence,
            "turn": metrics.turn,
            "channel": "telephone",
            "pipeline_mode": (
                ("streaming_asr_speculative_llm" if getattr(self.config, "speculative_llm", False)
                 else "streaming_asr") if getattr(self.config, "streaming_asr", False)
                else ("half_duplex_filler" if getattr(self.config, "filler_enabled", False) else "half_duplex")
            ),
            "outcome": outcome,
            "failure_stage": failure_stage or None,
            "error_code": error_code or None,
            "vad_energy_threshold": self.config.energy_threshold,
            "vad_preroll_ms": self.config.preroll_ms,
            "vad_speech_start_ms": self.config.speech_start_ms,
            "vad_speech_end_ms": self.config.speech_end_ms,
            "speech_duration_ms": utterance.speech_duration_ms,
            "utterance_ms": utterance.utterance_ms,
            "endpoint_silence_ms": utterance.endpoint_silence_ms,
            "endpoint_reason": utterance.endpoint_reason,
            "asr_ms": metrics.asr_ms,
            "asr_connect_ms": metrics.asr_connect_ms,
            "asr_final_after_speech_end_ms": metrics.asr_final_after_speech_end_ms,
            "end_of_detected_speech_to_llm_start_ms": metrics.end_of_detected_speech_to_llm_start_ms,
            "asr_partial_count": metrics.asr_partial_count,
            "asr_confirmed_count": metrics.asr_confirmed_count,
            "transcript_chars": metrics.transcript_chars,
            "llm_ms": metrics.llm_ms,
            "llm_speculative_requests": metrics.llm_speculative_requests,
            "llm_speculative_discarded": metrics.llm_speculative_discarded,
            "llm_speculative_failures": metrics.llm_speculative_failures,
            "llm_speculative_reused": metrics.llm_speculative_reused,
            "llm_speculative_lead_ms": metrics.llm_speculative_lead_ms,
            "llm_wait_after_asr_final_ms": metrics.llm_wait_after_asr_final_ms,
            "reply_chars": metrics.reply_chars,
            "filler_available": metrics.filler_available,
            "filler_blocks_started": metrics.filler_blocks_started,
            "filler_blocks_completed": metrics.filler_blocks_completed,
            "filler_audio_ms": metrics.filler_audio_ms,
            "beep_count": metrics.beep_count,
            "beep_audio_ms": metrics.beep_audio_ms,
            "end_of_detected_speech_to_first_beep_audio_ms": metrics.end_of_detected_speech_to_first_beep_audio_ms,
            "end_of_actual_speech_to_first_beep_audio_ms": metrics.end_of_actual_speech_to_first_beep_audio_ms,
            "end_of_detected_speech_to_first_filler_audio_ms": metrics.end_of_detected_speech_to_first_filler_audio_ms,
            "end_of_actual_speech_to_first_filler_audio_ms": metrics.end_of_actual_speech_to_first_filler_audio_ms,
            "reply_audio_wait_for_filler_ms": metrics.reply_audio_wait_for_filler_ms,
            "tts_backend": metrics.tts_backend,
            "tts_first_audio_generated_ms": metrics.tts_first_audio_generated_ms,
            "tts_first_audio_written_ms": metrics.tts_first_audio_written_ms,
            "tts_total_ms": metrics.tts_total_ms,
            "tts_audio_ms": metrics.tts_audio_ms,
            "end_of_detected_speech_to_first_reply_audio_ms": (
                metrics.end_of_detected_speech_to_first_reply_audio_ms
            ),
            "end_of_actual_speech_to_first_reply_audio_ms": (
                metrics.end_of_actual_speech_to_first_reply_audio_ms
            ),
            "audio_queue_dropped_frames": metrics.audio_queue_dropped_frames,
        }
        self.performance.submit(record)

    def _debug_event(
        self, event: str, values: Mapping[str, Any] | None = None
    ) -> dict[str, Any]:
        if not IDENTIFIER_RE.fullmatch(event):
            raise AgentError("debug_event_name_invalid")
        values = values or {}
        if any(key in SENSITIVE_DEBUG_KEYS for key in values):
            raise AgentError("sensitive_debug_field_in_public_event")
        self.debug_sequence += 1
        return {
            "protocol": DEBUG_PROTOCOL,
            "sequence": self.debug_sequence,
            "epoch_ms": time.time_ns() // 1_000_000,
            "monotonic_ms": time.monotonic_ns() // 1_000_000,
            "slot_id": self.config.slot_id(self.slot_index),
            "event": event,
            **dict(values),
        }

    def emit_debug(
        self,
        event: str,
        values: Mapping[str, Any] | None = None,
        sensitive: Mapping[str, Any] | None = None,
    ) -> None:
        try:
            public_event = self._debug_event(event, values)
            if sensitive is not None and any(
                key not in {
                    "text", "reply", "raw_response", "normalized_response"
                }
                for key in sensitive
            ):
                raise AgentError("sensitive_debug_field_invalid")
        except Exception as error:
            LOGGER.warning(
                "slot=%s event=debug_event_rejected code=%s",
                self.config.slot_id(self.slot_index),
                diagnostic_error_code(error),
            )
            return
        for subscriber_id, subscriber in tuple(self.debug_subscribers.items()):
            try:
                item = dict(public_event)
                if (
                    sensitive
                    and subscriber.show_text
                    and self.config.debug_allow_sensitive_console
                ):
                    item.update(sensitive)
                    item["sensitive"] = True
                if subscriber.queue.full():
                    with contextlib.suppress(asyncio.QueueEmpty):
                        subscriber.queue.get_nowait()
                    subscriber.dropped += 1
                if subscriber.dropped:
                    item["dropped_before"] = subscriber.dropped
                    subscriber.dropped = 0
                subscriber.queue.put_nowait(item)
            except Exception:
                self.debug_subscribers.pop(subscriber_id, None)

    def debug_callback(self) -> DebugCallback:
        loop = asyncio.get_running_loop()

        def callback(
            event: str,
            values: Mapping[str, Any],
            sensitive: Mapping[str, Any] | None,
        ) -> None:
            try:
                loop.call_soon_threadsafe(
                    self.emit_debug,
                    event,
                    dict(values),
                    dict(sensitive) if sensitive is not None else None,
                )
            except RuntimeError:
                pass

        return callback

    async def status_payload(self) -> dict[str, Any]:
        async with self.lock:
            self._cleanup_claims()
            if self.active_uuid:
                state_name = "in_call"
            elif self.pending:
                state_name = "reserved"
            else:
                state_name = "idle"
            return {
                "ok": True,
                "slot_id": self.config.slot_id(self.slot_index),
                "state": state_name,
                "sip_registered": self.sip_registered,
                "publisher_reachable": self.publisher_reachable,
                "audiosocket_format": TELEPHONY_FORMAT,
                "audiosocket_type": f"0x{AUDIO_TYPE_SLIN16:02x}",
                "audiosocket_sample_rate": TELEPHONY_RATE,
                "frame_ms": FRAME_MS,
                "frame_bytes": TELEPHONY_FRAME_BYTES,
            }

    async def debug_subscribe(
        self, message: Mapping[str, Any], writer: asyncio.StreamWriter
    ) -> None:
        requested = message.get("show_text", False)
        if not isinstance(requested, bool):
            raise ProtocolError("debug_show_text_invalid")
        if len(self.debug_subscribers) >= MAX_DEBUG_SUBSCRIBERS:
            raise ProtocolError("debug_subscriber_limit")
        peer_is_root = self.peer_uid(writer) == 0
        show_text = (
            requested
            and self.config.debug_allow_sensitive_console
            and peer_is_root
        )
        subscriber_id = self.debug_next_subscriber
        self.debug_next_subscriber += 1
        subscriber = DebugSubscriber(asyncio.Queue(maxsize=256), show_text)
        self.debug_subscribers[subscriber_id] = subscriber
        try:
            acknowledgement = {
                "ok": True,
                "protocol": DEBUG_PROTOCOL,
                "slot_id": self.config.slot_id(self.slot_index),
                "show_text": show_text,
                "sensitive_console_allowed": (
                    self.config.debug_allow_sensitive_console and peer_is_root
                ),
            }
            writer.write(json.dumps(acknowledgement, separators=(",", ":")).encode() + b"\n")
            status = await self.status_payload()
            snapshot = self._debug_event("slot_status", {
                "state": status["state"],
                "sip_registered": status["sip_registered"],
                "publisher_reachable": status["publisher_reachable"],
                "audiosocket_format": status["audiosocket_format"],
                "audiosocket_type": status["audiosocket_type"],
                "audiosocket_sample_rate": status["audiosocket_sample_rate"],
                "frame_ms": status["frame_ms"],
                "frame_bytes": status["frame_bytes"],
            })
            writer.write(json.dumps(snapshot, separators=(",", ":")).encode() + b"\n")
            await writer.drain()
            self.emit_debug("debug_subscriber_connected", {"show_text": show_text})
            while not self.stopping.is_set():
                try:
                    item = await asyncio.wait_for(subscriber.queue.get(), timeout=1.0)
                except asyncio.TimeoutError:
                    continue
                writer.write(json.dumps(item, separators=(",", ":")).encode() + b"\n")
                await writer.drain()
        finally:
            self.debug_subscribers.pop(subscriber_id, None)
            self.emit_debug("debug_subscriber_disconnected", {})

    @staticmethod
    def peer_uid(writer: asyncio.StreamWriter) -> int | None:
        peer_socket = writer.get_extra_info("socket")
        if peer_socket is None or not hasattr(socket, "SO_PEERCRED"):
            return None
        try:
            size = struct.calcsize("3i")
            credentials = peer_socket.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, size)
            _pid, uid, _gid = struct.unpack("3i", credentials)
            return int(uid)
        except (OSError, struct.error):
            return None

    def _cleanup_claims(self) -> bool:
        now = time.monotonic()
        before = len(self.pending)
        self.pending = {key: value for key, value in self.pending.items() if value.expires_at > now}
        expired = len(self.pending) != before
        self.expired_claim_pending = self.expired_claim_pending or expired
        if expired:
            self.emit_debug("claim_expired", {"count": before - len(self.pending)})
        return expired

    async def capacity_command(self, message: Mapping[str, Any]) -> Mapping[str, Any]:
        request = {"protocol": CONTROL_PROTOCOL, **message}
        was_reachable = self.publisher_reachable
        try:
            response = await asyncio.to_thread(
                unix_command, self.config.capacity_control_socket, request, 20.0
            )
            self.publisher_reachable = response.get("protocol") == CONTROL_PROTOCOL
            if self.publisher_reachable != was_reachable:
                self.emit_debug(
                    "publisher_reachability",
                    {"reachable": self.publisher_reachable},
                )
            return response
        except Exception:
            self.publisher_reachable = False
            if was_reachable:
                self.emit_debug("publisher_reachability", {"reachable": False})
            raise

    async def set_capacity_state(self, state: str, reason: str) -> bool:
        try:
            response = await self.capacity_command(
                {
                    "command": "set_slot_state",
                    "slot_id": self.config.slot_id(self.slot_index),
                    "state": state,
                    "reason": reason,
                }
            )
            return response.get("accepted") is True
        except Exception:
            return False

    async def get_call_policy(self, claim: Claim) -> dict[str, Any]:
        local = await self.capacity_command(
            {
                "command": "get_call_policy",
                "request_id": claim.request_id,
                "lease_id": claim.lease_id,
            }
        )
        network = local.get("response")
        if local.get("accepted") is not True or not isinstance(network, Mapping):
            raise ProtocolError("call_policy_unavailable")
        if (
            set(network) != {
                "protocol", "command", "accepted", "request_id", "lease_id", "policy"
            }
            or network.get("protocol") != PROTOCOL
            or network.get("command") != "get_call_policy_result"
            or network.get("accepted") is not True
            or network.get("request_id") != claim.request_id
            or network.get("lease_id") != claim.lease_id
        ):
            raise ProtocolError("call_policy_rejected")
        return validate_call_policy(network.get("policy"))

    async def publish_handoff(self, claim: Claim, action: str) -> None:
        target = ACTION_TARGETS.get(action)
        if target is None:
            raise ProtocolError("handoff_action_invalid")
        call_result = {
            "protocol": "kienzlefon-ai-call-result-v1",
            "request_id": claim.request_id,
            "lease_id": claim.lease_id,
            "outcome": "handoff_requested",
            "handoff_target": target,
            "commit_status": "not_committed",
        }
        local = await self.capacity_command(
            {"command": "publish_call_result", "result": call_result}
        )
        network = local.get("response")
        if local.get("accepted") is not True or not isinstance(network, Mapping):
            raise ProtocolError("handoff_publish_failed")
        if (
            set(network) != {
                "protocol", "command", "accepted", "request_id", "duplicate"
            }
            or network.get("protocol") != PROTOCOL
            or network.get("command") != "publish_call_result_result"
            or network.get("accepted") is not True
            or network.get("request_id") != claim.request_id
            or not isinstance(network.get("duplicate"), bool)
        ):
            raise ProtocolError("handoff_publish_rejected")

    async def commit_completed_orders(
        self, claim: Claim, state: ConversationState
    ) -> int:
        committed_now = 0
        failures = 0
        for order in state.orders:
            if not order.complete or order.committed:
                continue
            started = time.monotonic()
            try:
                order.call_id = await asyncio.to_thread(
                    commit_order,
                    self.config,
                    claim.request_id,
                    claim.caller_id,
                    order,
                )
                order.committed = True
                committed_now += 1
                self.emit_debug(
                    "order_commit_end",
                    {
                        "order_id": order.order_id,
                        "call_type": order.call_type,
                        "duration_ms": round((time.monotonic() - started) * 1000),
                    },
                )
            except Exception as error:
                failures += 1
                self.emit_debug(
                    "order_commit_error",
                    {
                        "order_id": order.order_id,
                        "call_type": order.call_type,
                        "code": diagnostic_error_code(error),
                    },
                )
        if failures:
            raise AgentError("order_commit_failed")
        return committed_now

    @staticmethod
    def pjsip_registration_status(output: str, registration: str) -> str | None:
        allowed_states = {"Registered", "Unregistered", "Rejected", "Stopped"}
        expected_prefix = registration + "/"
        for raw_line in output.splitlines():
            columns = raw_line.split()
            if not columns or not columns[0].startswith(expected_prefix):
                continue
            return next(
                (value for value in columns[1:] if value in allowed_states),
                None,
            )
        return None

    def sip_registration_is_ready(self) -> bool:
        registration = f"{self.config.slot_id(self.slot_index)}-registration"
        try:
            result = subprocess.run(
                ["/usr/sbin/asterisk", "-rx", f"pjsip show registration {registration}"],
                check=False,
                capture_output=True,
                text=True,
                timeout=2.0,
            )
        except (OSError, subprocess.SubprocessError):
            return False
        if result.returncode != 0:
            return False
        return self.pjsip_registration_status(result.stdout, registration) == "Registered"

    async def readiness_loop(self) -> None:
        while not self.stopping.is_set():
            registered = await asyncio.to_thread(self.sip_registration_is_ready)
            async with self.lock:
                self._cleanup_claims()
                expired = self.expired_claim_pending
                busy = self.active_uuid is not None or bool(self.pending)
                registration_changed = registered != self.sip_registered
                self.sip_registered = registered
                if registration_changed:
                    self.emit_debug("sip_registration", {"registered": registered})
                if expired:
                    await self.set_capacity_state("draining", "draining")
                    self.expired_claim_pending = False
                elif not busy:
                    desired = "ready" if registered else "not_ready"
                    reason = "ready" if desired == "ready" else "not_ready"
                    await self.set_capacity_state(desired, reason)
            try:
                await asyncio.wait_for(self.stopping.wait(), timeout=1.0)
            except asyncio.TimeoutError:
                pass

    async def control(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            raw = await asyncio.wait_for(reader.readline(), timeout=2.0)
            if not raw or len(raw) > 8192:
                raise ProtocolError("control_message_invalid")
            message = json.loads(raw)
            if not isinstance(message, Mapping):
                raise ProtocolError("control_not_object")
            command = message.get("command")
            if command == "debug_subscribe":
                try:
                    await self.debug_subscribe(message, writer)
                except (ConnectionError, BrokenPipeError, asyncio.IncompleteReadError):
                    pass
                except Exception:
                    with contextlib.suppress(Exception):
                        writer.write(b'{"ok":false,"reason":"rejected"}\n')
                        await writer.drain()
                finally:
                    writer.close()
                    with contextlib.suppress(Exception):
                        await writer.wait_closed()
                return
            if command == "claim":
                response = await self.claim(message)
            elif command == "status":
                response = await self.status_payload()
            elif command == "release":
                call_uuid = str(message.get("call_uuid", ""))
                async with self.lock:
                    accepted = self.pending.pop(call_uuid, None) is not None
                self.emit_debug("claim_released", {"accepted": accepted})
                response = {"ok": accepted}
            else:
                raise ProtocolError("control_command_unknown")
        except Exception:
            response = {"ok": False, "reason": "rejected"}
        writer.write(json.dumps(response, separators=(",", ":")).encode() + b"\n")
        await writer.drain()
        writer.close()
        await writer.wait_closed()

    async def claim(self, message: Mapping[str, Any]) -> dict[str, Any]:
        if message.get("protocol") != PROTOCOL:
            raise ProtocolError("protocol_mismatch")
        slot_id = _safe_identifier(message.get("slot_id"), "slot_id")
        if slot_id != self.config.slot_id(self.slot_index):
            raise ProtocolError("slot_mismatch")
        call_uuid = str(uuid.UUID(str(message.get("call_uuid", ""))))
        request_id = _safe_identifier(message.get("request_id"), "request_id")
        lease_id = _safe_identifier(message.get("lease_id"), "lease_id", lease=True)
        caller_id = _safe_caller(message.get("caller_id"))
        native_format = _safe_codec(message.get("native_format"))
        read_format = _safe_codec(message.get("read_format"))
        write_format = _safe_codec(message.get("write_format"))
        async with self.lock:
            self._cleanup_claims()
            if self.active_uuid is not None or self.pending:
                self.emit_debug("call_reservation_rejected", {"reason": "slot_busy"})
                return {"ok": False, "reason": "slot_busy"}
            self.pending[call_uuid] = Claim(
                call_uuid=call_uuid,
                request_id=request_id,
                lease_id=lease_id,
                caller_id=caller_id,
                native_format=native_format,
                read_format=read_format,
                write_format=write_format,
                expires_at=time.monotonic() + 10.0,
            )
        self.emit_debug("call_reserved", {
            "native_format": native_format or "unknown",
            "read_format": read_format or "unknown",
            "write_format": write_format or "unknown",
        })
        return {"ok": True}

    async def audiosocket(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        claim: Claim | None = None
        try:
            kind, payload = await asyncio.wait_for(read_audiosocket_frame(reader), timeout=5.0)
            if kind != UUID_TYPE or len(payload) != 16:
                raise ProtocolError("audiosocket_uuid_missing")
            call_uuid = str(uuid.UUID(bytes=payload))
            async with self.lock:
                self._cleanup_claims()
                claim = self.pending.pop(call_uuid, None)
                if claim is None or self.active_uuid is not None:
                    raise ProtocolError("audiosocket_claim_missing")
                self.active_uuid = call_uuid
                self.call_sequence += 1
            LOGGER.info("slot=%s event=call_started", self.config.slot_id(self.slot_index))
            self.emit_debug("call_started", {
                "native_format": claim.native_format or "unknown",
                "read_format": claim.read_format or "unknown",
                "write_format": claim.write_format or "unknown",
                "audiosocket_encoding": "pcm_s16le",
                "audiosocket_format": TELEPHONY_FORMAT,
                "audiosocket_type": f"0x{AUDIO_TYPE_SLIN16:02x}",
                "audiosocket_sample_rate": TELEPHONY_RATE,
                "audiosocket_channels": 1,
                "frame_ms": FRAME_MS,
                "frame_bytes": TELEPHONY_FRAME_BYTES,
            })
            await self.run_call(claim, reader, writer)
        except (
            asyncio.IncompleteReadError,
            ConnectionError,
            ProtocolError,
            asyncio.TimeoutError,
        ) as error:
            self.emit_debug(
                "call_transport_error", {"code": diagnostic_error_code(error)}
            )
            LOGGER.warning(
                "slot=%s event=call_transport_failed",
                self.config.slot_id(self.slot_index),
            )
        except Exception as error:
            self.emit_debug(
                "call_internal_error", {"code": diagnostic_error_code(error)}
            )
            LOGGER.error(
                "slot=%s event=call_internal_failure code=%s",
                self.config.slot_id(self.slot_index),
                diagnostic_error_code(error),
            )
        finally:
            async with self.lock:
                if claim is not None and self.active_uuid == claim.call_uuid:
                    await self.set_capacity_state("draining", "draining")
                    self.active_uuid = None
            with contextlib.suppress(Exception):
                writer.close()
                await writer.wait_closed()
            self.emit_debug("call_finished", {})
            LOGGER.info("slot=%s event=call_finished", self.config.slot_id(self.slot_index))

    async def run_call(
        self,
        claim: Claim,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        incoming: asyncio.Queue[bytes | BaseException | None] = asyncio.Queue(maxsize=1000)
        audio_input_stats = AudioInputStats()
        write_lock = asyncio.Lock()
        listening = asyncio.Event()
        read_task = asyncio.create_task(
            self.audio_reader(reader, incoming, listening, audio_input_stats)
        )
        tts_active = asyncio.Event()
        silence_task: asyncio.Task[None] | None = None
        state = ConversationState(channel="telephone", caller_id=claim.caller_id)
        committed_count = 0
        handoff_published = False
        stage = "greeting_tts"
        debug = self.debug_callback()
        active_performance: TurnPerformance | None = None
        active_asr: StreamingASRSession | None = None
        active_speculation: SpeculativeLLMTurn | None = None
        active_filler: FillerPlayback | None = None

        def input_finished(_task: asyncio.Task[Any]) -> None:
            # Stop local playback even during an in-flight, non-cancellable
            # durable commit. await_phase subsequently classifies the hangup.
            if active_filler is not None:
                active_filler.ready.set()
                active_filler.task.cancel()

        read_task.add_done_callback(input_finished)

        async def stop_filler() -> None:
            nonlocal active_filler
            if active_filler is not None:
                await active_filler.close()
                active_filler = None

        async def await_phase(awaitable: Any) -> Any:
            # Hangup wins ties: never release a result after the caller left.
            task = asyncio.create_task(awaitable)
            try:
                while True:
                    watched = {task, read_task}
                    if active_filler is not None and not active_filler.task.done():
                        watched.add(active_filler.task)
                    if not read_task.done():
                        await asyncio.wait(watched, return_when=asyncio.FIRST_COMPLETED)
                    if read_task.done():
                        task.cancel()
                        await stop_filler()
                        self.clear_audio_queue(incoming)
                        terminal = incoming.get_nowait() if not incoming.empty() else None
                        if isinstance(terminal, BaseException):
                            raise terminal
                        raise CallerHangup("caller_hangup")
                    if active_filler is not None and active_filler.task.done():
                        await active_filler.task  # propagate transport failure, not task warnings
                    if task.done():
                        return await task
            finally:
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)

        def change_stage(name: str) -> None:
            nonlocal stage
            stage = name
            if name == "vad":
                listening.set()
            else:
                listening.clear()
            self.emit_debug("pipeline_stage", {"stage": name})

        async def speak_guarded(
            text: str,
            *,
            allow_fallback: bool = True,
            purpose: str = "dialog",
        ) -> TTSMetrics:
            filler = active_filler if purpose == "reply" else None
            if filler is None:
                await stop_filler()
                tts_active.set()

            async def take_audio_output() -> None:
                assert filler is not None
                await filler.release_to_reply()
                tts_active.set()

            try:
                operation = self.speak(
                    text,
                    writer,
                    write_lock,
                    allow_fallback=allow_fallback,
                    purpose=purpose,
                    **({"before_first_audio": take_audio_output} if filler is not None else {}),
                )
                return await await_phase(operation)
            finally:
                await stop_filler()
                tts_active.clear()

        async def stop_silence() -> None:
            nonlocal silence_task
            if silence_task is None:
                return
            silence_task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await silence_task
            silence_task = None

        async def speak_reply(text: str) -> None:
            nonlocal active_performance
            metrics = await speak_guarded(text, purpose="reply")
            if active_performance is None:
                return
            apply_tts_performance(active_performance, metrics, len(text))
            self.record_turn_performance(active_performance, "completed")
            active_performance = None

        try:
            change_stage("greeting_tts")
            await speak_guarded(self.config.greeting, purpose="greeting")
            self.clear_audio_queue(incoming)
            silence_task = asyncio.create_task(
                self.silence_writer(writer, write_lock, tts_active)
            )
            for turn in range(1, self.config.max_turns + 1):
                while True:
                    change_stage("vad")
                    if active_asr is not None:
                        await active_asr.close()
                    if active_speculation is not None:
                        await active_speculation.close()
                    active_speculation = (
                        SpeculativeLLMTurn(self.config, state, lambda: self.get_call_policy(claim), self.slot_index)
                        if (getattr(self.config, "streaming_asr", False)
                            and getattr(self.config, "speculative_llm", False)) else None
                    )
                    active_asr = (
                        StreamingASRSession(self.config, debug,
                            active_speculation.offer if active_speculation else None)
                        if getattr(self.config, "streaming_asr", False) else None
                    )
                    queue_dropped_before = audio_input_stats.queue_dropped_frames
                    utterance = await self.next_utterance(incoming, active_asr)
                    if utterance is None:
                        if active_asr is not None:
                            await active_asr.close()
                            active_asr = None
                        change_stage("commit")
                        prepare_lossless_terminal_orders(state)
                        committed_count += await self.commit_completed_orders(claim, state)
                        return
                    if not utterance.pcm:
                        continue
                    active_performance = TurnPerformance(
                        turn=turn,
                        utterance=utterance,
                        audio_queue_dropped_frames=(
                            audio_input_stats.queue_dropped_frames
                            - queue_dropped_before
                        ),
                    )
                    if getattr(self.config, "filler_enabled", False):
                        active_performance.filler_available = int(any(self.filler_clips))
                        if any(self.filler_clips) or self.filler_beep:
                            active_filler = FillerPlayback(
                                self.filler_clips, writer, write_lock, tts_active, active_performance,
                                self.config, self.filler_beep)
                    change_stage("asr")
                    try:
                        if active_asr is not None:
                            final_task = asyncio.create_task(active_asr.finish())
                            try:
                                done, _ = await asyncio.wait(
                                    {final_task, read_task},
                                    return_when=asyncio.FIRST_COMPLETED,
                                )
                                if read_task in done:
                                    await active_asr.close()
                                    if active_speculation is not None:
                                        await active_speculation.close()
                                        active_speculation.update_metrics(active_performance)
                                    self.clear_audio_queue(incoming)
                                    terminal = incoming.get_nowait()
                                    if isinstance(terminal, BaseException):
                                        raise terminal
                                    self.record_turn_performance(
                                        active_performance, "caller_hangup", "asr"
                                    )
                                    active_performance = None
                                    change_stage("commit")
                                    prepare_lossless_terminal_orders(state)
                                    committed_count += await self.commit_completed_orders(claim, state)
                                    return
                                asr_result = await final_task
                            finally:
                                final_task.cancel()
                                await asyncio.gather(final_task, return_exceptions=True)
                        else:
                            asr_result = await await_phase(
                                batch_asr_transcribe(self.config, utterance.pcm, debug))
                        active_performance.asr_final_after_speech_end_ms = round(
                            (time.monotonic_ns() - utterance.endpoint_detected_monotonic_ns)
                            / 1_000_000
                        )
                    except ProtocolError as error:
                        if diagnostic_error_code(error) == "asr_empty_confirmed_transcript":
                            await stop_filler()
                            self.emit_debug("asr_empty_ignored", {"turn": turn})
                            if active_speculation is not None:
                                await active_speculation.close()
                                active_speculation.update_metrics(active_performance)
                            self.record_turn_performance(
                                active_performance,
                                "asr_empty",
                                "asr",
                                "asr_empty_confirmed_transcript",
                            )
                            active_performance = None
                            continue
                        raise
                    finally:
                        if active_asr is not None:
                            await active_asr.close()
                            active_asr = None
                    transcript = asr_result.transcript
                    active_performance.asr_ms = asr_result.duration_ms
                    active_performance.asr_connect_ms = asr_result.connect_ms
                    active_performance.asr_partial_count = asr_result.partial_count
                    active_performance.asr_confirmed_count = asr_result.confirmed_count
                    active_performance.transcript_chars = len(transcript)
                    asr_final_ns = time.monotonic_ns()
                    break
                change_stage("llm")
                if active_speculation is not None:
                    accepted_task = asyncio.create_task(active_speculation.finish(transcript, state))
                    try:
                        done, _ = await asyncio.wait({accepted_task, read_task},
                                                     return_when=asyncio.FIRST_COMPLETED)
                        if read_task in done:
                            accepted_task.cancel()
                            await asyncio.gather(accepted_task, return_exceptions=True)
                            await active_speculation.close()
                            active_speculation.update_metrics(active_performance)
                            self.clear_audio_queue(incoming)
                            terminal = incoming.get_nowait()
                            if isinstance(terminal, BaseException):
                                raise terminal
                            self.record_turn_performance(active_performance, "caller_hangup", "llm")
                            active_performance = None
                            change_stage("commit")
                            prepare_lossless_terminal_orders(state)
                            committed_count += await self.commit_completed_orders(claim, state)
                            return
                        result, accepted_state = await accepted_task
                        state = accepted_state
                    finally:
                        accepted_task.cancel()
                        await asyncio.gather(accepted_task, return_exceptions=True)
                    active_speculation.update_metrics(active_performance)
                    await active_speculation.close()
                    active_speculation = None
                    llm_ms = active_performance.llm_ms or 0
                else:
                    policy = await await_phase(self.get_call_policy(claim))
                    llm_started = time.monotonic()
                    active_performance.end_of_detected_speech_to_llm_start_ms = round(
                        (time.monotonic_ns() - utterance.endpoint_detected_monotonic_ns) / 1_000_000
                    )
                    self.emit_debug("llm_start", {
                        "turn": turn,
                        "input_chars": len(transcript),
                        "practice_open": policy.get("practice_open"),
                        "phone_open": policy.get("phone_open"),
                        "practice_queue_allowed": policy.get("practice_queue_allowed"),
                        "pharmacy_transfer_allowed": policy.get("pharmacy_transfer_allowed"),
                        "specialist_transfer_allowed": policy.get("specialist_transfer_allowed"),
                    })
                    accepted_state = copy.deepcopy(state)
                    result = await await_phase(call_llm_async(self.config, accepted_state, transcript, policy))
                    state = accepted_state
                    llm_ms = round((time.monotonic() - llm_started) * 1000)
                    active_performance.llm_ms = llm_ms
                active_performance.llm_wait_after_asr_final_ms = round(
                    (time.monotonic_ns() - asr_final_ns) / 1_000_000
                )
                self.emit_debug(
                    "llm_end",
                    {
                        "turn": turn,
                        "duration_ms": llm_ms,
                        "reply_chars": len(result.reply),
                        "order_count": len(result.orders),
                        "complete_order_count": sum(
                            order.complete for order in result.orders
                        ),
                        "action": result.action,
                        "repair_count": len(result.repairs),
                    },
                    {
                        "reply": result.reply,
                        "raw_response": result.raw,
                        "normalized_response": {
                            "reply": result.reply,
                            "action": result.action,
                            "orders": [order_payload(order) for order in result.orders],
                        },
                    },
                )
                apply_llm_result(state, result, transcript)
                if result.action == "beenden":
                    change_stage("commit")
                    prepare_lossless_terminal_orders(state)
                    committed_count += await self.commit_completed_orders(claim, state)
                    change_stage("reply_tts")
                    await speak_reply(result.reply)
                    change_stage("terminate")
                    await stop_silence()
                    await write_audiosocket_frame(writer, write_lock, TERMINATE_TYPE)
                    return
                if result.action in ACTION_TARGETS:
                    protected_handoff_record = any(
                        marker in result.repairs
                        for marker in (
                            "role_route_patient_emergency",
                            "role_route_professional_urgent",
                            "role_route_professional_urgent_outside_hours",
                            "role_route_care_service",
                            "role_route_care_service_outside_hours",
                            "au_handoff",
                        )
                    )

                    if protected_handoff_record:
                        change_stage("protected_handoff_commit")

                        # Bei Notfall oder unsicherer Weiterleitung wird die
                        # Dokumentation vor dem Handoff bestmöglich persistiert.
                        # Ein Commitfehler darf die Weiterleitung nicht blockieren.
                        try:
                            committed_count += await self.commit_completed_orders(
                                claim, state
                            )
                        except Exception as protected_commit_error:
                            self.emit_debug(
                                "protected_handoff_commit_error",
                                {
                                    "code": diagnostic_error_code(
                                        protected_commit_error
                                    )
                                },
                            )

                    change_stage("handoff_policy")
                    current_policy = await self.get_call_policy(claim)
                    if (
                        result.action != "rotes_telefon"
                        and current_policy.get(ACTION_POLICY_FIELDS[result.action]) is not True
                    ):
                        state.action = "none"
                        change_stage("reply_tts")
                        await speak_reply(
                            "Diese Weiterleitung ist aktuell nicht verfügbar. "
                            "Kann ich Ihnen noch anders helfen?"
                        )
                        continue
                    change_stage("handoff_publish")
                    await self.publish_handoff(claim, result.action)
                    handoff_published = True
                    change_stage("reply_tts")
                    await speak_reply(result.reply)
                    change_stage("terminate")
                    await stop_silence()
                    await write_audiosocket_frame(writer, write_lock, TERMINATE_TYPE)
                    return
                change_stage("reply_tts")
                await speak_reply(result.reply)
                self.clear_audio_queue(incoming)
            change_stage("turn_limit")
            prepare_lossless_terminal_orders(state)
            committed_count += await self.commit_completed_orders(claim, state)
            raise AgentError("dialog_turn_limit")
        except CallerHangup:
            await stop_filler()
            if active_performance is not None:
                self.record_turn_performance(active_performance, "caller_hangup", stage)
                active_performance = None
            if not handoff_published:
                prepare_lossless_terminal_orders(state)
                await self.commit_completed_orders(claim, state)
        except Exception as error:
            failed_stage = stage
            await stop_filler()
            if active_speculation is not None:
                # Stop provisional GPU work before committing confirmed state or
                # speaking the technical failure, including ASR/VAD failures.
                await active_speculation.close()
            if active_performance is not None:
                if active_speculation is not None:
                    active_speculation.update_metrics(active_performance)
                self.record_turn_performance(
                    active_performance,
                    "failed",
                    failed_stage,
                    diagnostic_error_code(error),
                )
                active_performance = None
            commit_error: BaseException | None = None
            if not handoff_published:
                try:
                    change_stage("commit")
                    prepare_lossless_terminal_orders(state)
                    committed_count += await self.commit_completed_orders(claim, state)
                except Exception as candidate_error:
                    commit_error = candidate_error
            self.emit_debug("pipeline_error", {
                "stage": stage,
                "code": diagnostic_error_code(error),
                "committed_order_count": sum(order.committed for order in state.orders),
                "commit_error": (
                    diagnostic_error_code(commit_error) if commit_error else "none"
                ),
            })
            LOGGER.warning(
                "slot=%s event=pipeline_failed stage=%s code=%s committed_orders=%d",
                self.config.slot_id(self.slot_index),
                stage,
                diagnostic_error_code(error),
                sum(order.committed for order in state.orders),
            )
            transport_failed = diagnostic_error_code(error) in {
                "audiosocket_input_failed", "IncompleteReadError",
                "ConnectionError", "BrokenPipeError",
            }
            if not transport_failed and not handoff_published:
                with contextlib.suppress(Exception):
                    await speak_guarded(
                        self.config.technical_failure,
                        allow_fallback=True,
                        purpose="technical_failure",
                    )
            await stop_silence()
            with contextlib.suppress(Exception):
                await write_audiosocket_frame(writer, write_lock, TERMINATE_TYPE)
        finally:
            await stop_filler()
            if active_asr is not None:
                await active_asr.close()
            if active_speculation is not None:
                await active_speculation.close()
            await stop_silence()
            read_task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await read_task

    async def silence_writer(
        self,
        writer: asyncio.StreamWriter,
        lock: asyncio.Lock,
        tts_active: asyncio.Event,
    ) -> None:
        """Send continuous silent PCM while the assistant is not speaking."""
        payload = b"\x00" * TELEPHONY_FRAME_BYTES
        interval = FRAME_MS / 1000.0
        self.emit_debug(
            "audiosocket_silence_started",
            {
                "frame_ms": FRAME_MS,
                "frame_bytes": TELEPHONY_FRAME_BYTES,
                "interval_ms": round(interval * 1000),
            },
        )
        try:
            while True:
                await asyncio.sleep(interval)
                if not tts_active.is_set():
                    async with lock:
                        if not tts_active.is_set():
                            writer.write(
                                bytes([AUDIO_TYPE_SLIN16])
                                + struct.pack("!H", len(payload))
                                + payload
                            )
                            await writer.drain()
        except asyncio.CancelledError:
            raise
        finally:
            self.emit_debug("audiosocket_silence_stopped", {})

    async def audio_reader(
        self,
        reader: asyncio.StreamReader,
        queue: asyncio.Queue[bytes | BaseException | None],
        listening: asyncio.Event | None = None,
        stats: AudioInputStats | None = None,
    ) -> None:
        if listening is None:
            listening = asyncio.Event()
            listening.set()
        remainder = bytearray()
        frame_bytes = TELEPHONY_FRAME_BYTES
        cancelled = False
        terminal: BaseException | None = None
        discarded_frames = 0
        overrun_frames = 0
        discarding = False
        self.emit_debug("audiosocket_input_ready", {
            "encoding": "pcm_s16le",
            "format": TELEPHONY_FORMAT,
            "type": f"0x{AUDIO_TYPE_SLIN16:02x}",
            "sample_rate": TELEPHONY_RATE,
            "channels": 1,
            "frame_ms": FRAME_MS,
            "frame_bytes": frame_bytes,
        })
        try:
            while True:
                kind, payload = await read_audiosocket_frame(reader)
                if kind == TERMINATE_TYPE:
                    break
                if kind == DTMF_TYPE:
                    continue
                if kind == ERROR_TYPE:
                    raise ProtocolError("audiosocket_remote_error")
                if kind != AUDIO_TYPE_SLIN16:
                    raise ProtocolError("audiosocket_audio_format_invalid")
                if not listening.is_set():
                    remainder.clear()
                    discarded_frames += max(1, len(payload) // frame_bytes)
                    if not discarding:
                        discarding = True
                        self.emit_debug("audio_discard_started", {})
                    continue
                if discarding:
                    self.emit_debug(
                        "audio_discard_ended", {"discarded_frames": discarded_frames}
                    )
                    discarding = False
                remainder.extend(payload)
                while len(remainder) >= frame_bytes:
                    frame = bytes(remainder[:frame_bytes])
                    del remainder[:frame_bytes]
                    if queue.full():
                        queue.get_nowait()
                        overrun_frames += 1
                        if stats is not None:
                            stats.queue_dropped_frames += 1
                    queue.put_nowait(frame)
        except asyncio.CancelledError:
            cancelled = True
            raise
        except Exception as error:
            terminal = ProtocolError("audiosocket_input_failed")
            self.emit_debug(
                "audiosocket_input_error", {"code": diagnostic_error_code(error)}
            )
        finally:
            if discarding:
                self.emit_debug(
                    "audio_discard_ended", {"discarded_frames": discarded_frames}
                )
            if overrun_frames:
                self.emit_debug(
                    "audio_queue_overrun", {"dropped_frames": overrun_frames}
                )
            if not cancelled:
                while queue.full():
                    queue.get_nowait()
                queue.put_nowait(terminal)

    async def next_utterance(
        self, queue: asyncio.Queue[bytes | BaseException | None],
        asr_stream: StreamingASRSession | None = None,
    ) -> UtteranceResult | None:
        vad = EnergyVAD(self.config)
        next_metrics = time.monotonic()
        while True:
            frame = await queue.get()
            if frame is None:
                if vad.active:
                    self.emit_debug("speech_end", {
                        "endpoint_reason": "hangup",
                        "accepted": False,
                        "utterance_ms": len(vad.frames) * FRAME_MS,
                        "speech_ms": vad.speech_frames * FRAME_MS,
                    })
                return None
            if isinstance(frame, BaseException):
                raise frame
            was_active = vad.active
            result = vad.feed(frame)
            if vad.started:
                self.emit_debug("speech_start", {
                    "rms": vad.last_energy,
                    "peak": vad.last_peak,
                    "threshold": vad.threshold,
                    "preroll_ms": max(0, len(vad.frames) - vad.speech_run) * FRAME_MS,
                    "speech_start_ms": vad.start_frames * FRAME_MS,
                })
            if asr_stream is not None:
                if vad.started:
                    asr_stream.start(b"".join(vad.frames))
                elif was_active:
                    asr_stream.feed(frame)
                # Queue.get need not yield with buffered AudioSocket frames.
                # Let connection, sender and receiver progress concurrently.
                await asyncio.sleep(0)
            now = time.monotonic()
            if now >= next_metrics:
                self.emit_debug("audio_level", {
                    "rms": vad.last_energy,
                    "peak": vad.last_peak,
                    "threshold": vad.threshold,
                    "vad_active": vad.active,
                    "queue_depth": queue.qsize(),
                })
                next_metrics = now + self.config.debug_metrics_interval_ms / 1000.0
            if result is not None:
                endpoint_detected_ns = time.monotonic_ns()
                endpoint_silence_ms = vad.last_silence_frames * FRAME_MS
                self.emit_debug("speech_end", {
                    "endpoint_reason": vad.last_end_reason,
                    "accepted": vad.last_accepted,
                    "utterance_ms": vad.last_frame_count * FRAME_MS,
                    "speech_ms": vad.last_speech_frames * FRAME_MS,
                    "trailing_silence_ms": endpoint_silence_ms,
                    "audio_bytes": vad.last_frame_count * TELEPHONY_RATE * PCM_WIDTH * FRAME_MS // 1000,
                })
                return UtteranceResult(
                    pcm=result,
                    speech_duration_ms=vad.last_speech_frames * FRAME_MS,
                    utterance_ms=vad.last_frame_count * FRAME_MS,
                    endpoint_silence_ms=endpoint_silence_ms,
                    endpoint_reason=vad.last_end_reason,
                    endpoint_detected_monotonic_ns=endpoint_detected_ns,
                    actual_speech_end_monotonic_ns=(
                        endpoint_detected_ns - endpoint_silence_ms * 1_000_000
                    ),
                )

    @staticmethod
    def clear_audio_queue(
        queue: asyncio.Queue[bytes | BaseException | None]
    ) -> None:
        terminal_found = False
        terminal: BaseException | None = None
        while True:
            try:
                value = queue.get_nowait()
            except asyncio.QueueEmpty:
                break
            if not isinstance(value, bytes):
                terminal_found = True
                terminal = value
        if terminal_found:
            queue.put_nowait(terminal)

    async def speak(
        self,
        text: str,
        writer: asyncio.StreamWriter,
        lock: asyncio.Lock,
        allow_fallback: bool = True,
        purpose: str = "dialog",
        before_first_audio: Callable[[], Any] | None = None,
    ) -> TTSMetrics:
        if not IDENTIFIER_RE.fullmatch(purpose):
            raise AgentError("tts_purpose_invalid")
        loop = asyncio.get_running_loop()
        blocks: asyncio.Queue[bytes | BaseException | None] = asyncio.Queue()
        cancelled = threading.Event()
        emitted_any = False
        # Deterministic speech-only number/date/time guard.
        # result.reply and all structured data stay unchanged.
        if purpose == "reply":
            normalized_text = normalize_tts_text(text)
            # Fail open if expansion would exceed the existing
            # TTS protocol length limit.
            if len(normalized_text) <= REPLY_LIMIT:
                text = normalized_text

        selected_backend = self.config.tts_backend
        started = time.monotonic()
        started_ns = time.monotonic_ns()
        audio_bytes = 0
        first_audio_reported = False
        first_audio_generated_ms: int | None = None
        first_audio_written_ms: int | None = None
        first_audio_written_ns: int | None = None
        self.emit_debug(
            "tts_start",
            {
                "backend": selected_backend,
                "purpose": purpose,
                "input_chars": len(text),
            },
            {"text": text},
        )

        def notify(event: str, values: Mapping[str, Any]) -> None:
            try:
                loop.call_soon_threadsafe(self.emit_debug, event, dict(values))
            except RuntimeError:
                pass

        def emit(block: bytes) -> None:
            nonlocal emitted_any
            if cancelled.is_set():
                raise AgentError("tts_cancelled")
            emitted_any = True
            loop.call_soon_threadsafe(blocks.put_nowait, block)

        def post_result(value: BaseException | None) -> None:
            if not cancelled.is_set():
                with contextlib.suppress(RuntimeError):
                    loop.call_soon_threadsafe(blocks.put_nowait, value)

        def worker() -> None:
            nonlocal selected_backend
            try:
                stream_tts(
                    self.config,
                    text,
                    self.config.tts_backend,
                    emit,
                    notify,
                )
            except Exception as primary:
                if cancelled.is_set():
                    return
                fallback = "piper" if self.config.tts_backend == "qwen" else "qwen"
                if emitted_any or not allow_fallback:
                    notify("tts_backend_error", {
                        "backend": self.config.tts_backend,
                        "purpose": purpose,
                        "code": diagnostic_error_code(primary),
                        "fallback_allowed": allow_fallback,
                    })
                    post_result(primary)
                    return
                selected_backend = fallback
                notify("tts_fallback", {
                    "from_backend": self.config.tts_backend,
                    "to_backend": fallback,
                    "purpose": purpose,
                    "code": diagnostic_error_code(primary),
                })
                try:
                    stream_tts(self.config, text, fallback, emit, notify)
                except Exception as fallback_error:
                    if cancelled.is_set():
                        return
                    notify("tts_backend_error", {
                        "backend": fallback,
                        "purpose": purpose,
                        "code": diagnostic_error_code(fallback_error),
                        "fallback_allowed": False,
                    })
                    post_result(primary)
                    return
            post_result(None)

        thread_task = asyncio.create_task(asyncio.to_thread(worker))
        pending = bytearray()
        frame_bytes = TELEPHONY_FRAME_BYTES
        deadline = loop.time()
        try:
            while True:
                item = await blocks.get()
                if item is None:
                    break
                if isinstance(item, BaseException):
                    raise AgentError("tts_failed") from item
                if not first_audio_reported:
                    first_audio_reported = True
                    first_audio_generated_ms = round(
                        (time.monotonic_ns() - started_ns) / 1_000_000
                    )
                    self.emit_debug("tts_first_audio", {
                        "backend": selected_backend,
                        "purpose": purpose,
                        "latency_ms": round((time.monotonic() - started) * 1000),
                    })
                audio_bytes += len(item)
                pending.extend(item)
                while len(pending) >= frame_bytes:
                    frame = bytes(pending[:frame_bytes])
                    del pending[:frame_bytes]
                    if first_audio_written_ns is None:
                        if before_first_audio is not None:
                            await before_first_audio()
                        # Do not burst buffered reply frames after a filler/TTS wait.
                        deadline = loop.time()
                    await write_audiosocket_frame(
                        writer, lock, AUDIO_TYPE_SLIN16, frame
                    )
                    if first_audio_written_ns is None:
                        first_audio_written_ns = time.monotonic_ns()
                        first_audio_written_ms = round(
                            (first_audio_written_ns - started_ns) / 1_000_000
                        )
                        self.emit_debug("tts_first_audio_written", {
                            "backend": selected_backend,
                            "purpose": purpose,
                            "latency_ms": first_audio_written_ms,
                        })
                    deadline += FRAME_MS / 1000.0
                    await asyncio.sleep(max(0.0, deadline - loop.time()))
            if pending:
                pending.extend(b"\0" * (frame_bytes - len(pending)))
                if first_audio_written_ns is None:
                    if before_first_audio is not None:
                        await before_first_audio()
                    deadline = loop.time()
                await write_audiosocket_frame(
                    writer, lock, AUDIO_TYPE_SLIN16, bytes(pending)
                )
                if first_audio_written_ns is None:
                    first_audio_written_ns = time.monotonic_ns()
                    first_audio_written_ms = round(
                        (first_audio_written_ns - started_ns) / 1_000_000
                    )
                    self.emit_debug("tts_first_audio_written", {
                        "backend": selected_backend,
                        "purpose": purpose,
                        "latency_ms": first_audio_written_ms,
                    })
                deadline += FRAME_MS / 1000.0
                await asyncio.sleep(max(0.0, deadline - loop.time()))
        except asyncio.CancelledError:
            # Playback stops immediately. The bounded synchronous TTS read exits
            # on its next chunk/timeout; it cannot send audio or start a fallback.
            cancelled.set()
            thread_task.cancel()
            await asyncio.gather(thread_task, return_exceptions=True)
            raise
        finally:
            if not cancelled.is_set():
                await thread_task
        duration_ms = round((time.monotonic() - started) * 1000)
        audio_ms = audio_bytes * 1000 // (TELEPHONY_RATE * PCM_WIDTH)
        self.emit_debug("tts_end", {
            "backend": selected_backend,
            "purpose": purpose,
            "duration_ms": duration_ms,
            "audio_bytes": audio_bytes,
            "audio_ms": audio_ms,
        })
        return TTSMetrics(
            backend=selected_backend,
            first_audio_generated_ms=first_audio_generated_ms,
            first_audio_written_ms=first_audio_written_ms,
            first_audio_written_monotonic_ns=first_audio_written_ns,
            duration_ms=duration_ms,
            audio_ms=audio_ms,
        )

    async def run(self) -> None:
        socket_path = self.config.control_socket(self.slot_index)
        socket_path.parent.mkdir(parents=True, exist_ok=True)
        socket_path.unlink(missing_ok=True)
        control_server = await asyncio.start_unix_server(self.control, path=str(socket_path))
        os.chmod(socket_path, 0o660)
        media_server = await asyncio.start_server(
            self.audiosocket,
            host="127.0.0.1",
            port=self.config.audio_port(self.slot_index),
            reuse_address=True,
        )
        LOGGER.info(
            "slot=%s event=started audio_port=%d",
            self.config.slot_id(self.slot_index),
            self.config.audio_port(self.slot_index),
        )
        self.emit_debug("agent_started", {
            "audio_port": self.config.audio_port(self.slot_index),
            "debug_metrics_interval_ms": self.config.debug_metrics_interval_ms,
            "sensitive_console_allowed": self.config.debug_allow_sensitive_console,
        })
        await self.set_capacity_state("not_ready", "not_ready")
        readiness_task = asyncio.create_task(self.readiness_loop())
        try:
            await self.stopping.wait()
        finally:
            self.emit_debug("agent_stopping", {})
            async with self.lock:
                await self.set_capacity_state("not_ready", "maintenance")
            readiness_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await readiness_task
            control_server.close()
            media_server.close()
            await control_server.wait_closed()
            await media_server.wait_closed()
            socket_path.unlink(missing_ok=True)
            self.performance.close()


def agi_command(command: str) -> str:
    print(command, flush=True)
    response = sys.stdin.readline()
    if not response:
        raise ProtocolError("agi_closed")
    return response.rstrip("\r\n")


def agi_get(name: str) -> str:
    response = agi_command(f"GET FULL VARIABLE ${{{name}}}")
    match = re.fullmatch(r"200 result=1 \((.*)\)", response)
    return match.group(1) if match else ""


def agi_set(name: str, value: str) -> None:
    response = agi_command(f'SET VARIABLE {name} "{value}"')
    if not response.startswith("200 result=1"):
        raise ProtocolError("agi_set_failed")


def guard(config: AgentConfig, slot_index: int) -> int:
    while True:
        line = sys.stdin.readline()
        if not line or line in {"\n", "\r\n"}:
            break
    accepted = False
    call_uuid = ""
    try:
        protocol = agi_get("KZF_AI_PROTOCOL")
        request_id = _safe_identifier(agi_get("KZF_AI_REQUEST_ID"), "request_id")
        lease_id = _safe_identifier(agi_get("KZF_AI_LEASE_ID"), "lease_id", lease=True)
        slot_id = _safe_identifier(agi_get("KZF_AI_HEADER_SLOT"), "slot_id")
        call_uuid = str(uuid.UUID(agi_get("KZF_AI_CALL_UUID")))
        caller_id = _safe_caller(agi_get("CALLERID(num)"))
        native_format = _safe_codec(agi_get("CHANNEL(audionativeformat)"))
        read_format = _safe_codec(agi_get("CHANNEL(audioreadformat)"))
        write_format = _safe_codec(agi_get("CHANNEL(audiowriteformat)"))
        message = {
            "command": "claim",
            "protocol": protocol,
            "slot_id": slot_id,
            "request_id": request_id,
            "lease_id": lease_id,
            "call_uuid": call_uuid,
            "caller_id": caller_id,
            "native_format": native_format,
            "read_format": read_format,
            "write_format": write_format,
        }
        response = unix_command(config.control_socket(slot_index), message)
        if response.get("ok") is True:
            publisher_response = unix_command(
                config.capacity_control_socket,
                {
                    "protocol": CONTROL_PROTOCOL,
                    "command": "claim_lease",
                    "slot_id": slot_id,
                    "lease_id": lease_id,
                    "request_id": request_id,
                },
            )
            accepted = publisher_response.get("accepted") is True
    except Exception:
        accepted = False
    with contextlib.suppress(Exception):
        agi_set("KZF_AI_GUARD_ACCEPTED", "1" if accepted else "0")
    if not accepted and call_uuid:
        with contextlib.suppress(Exception):
            unix_command(
                config.control_socket(slot_index),
                {"command": "release", "call_uuid": call_uuid},
            )
    return 0


def unix_command(
    path: Path, message: Mapping[str, Any], timeout: float = 5.0
) -> Mapping[str, Any]:
    body = json.dumps(message, separators=(",", ":")).encode() + b"\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(timeout)
        client.connect(str(path))
        client.sendall(body)
        response = bytearray()
        while not response.endswith(b"\n"):
            if len(response) > MAX_CONTROL_RESPONSE_BYTES:
                raise ProtocolError("control_response_too_large")
            block = client.recv(4096)
            if not block:
                raise ProtocolError("control_response_closed")
            response.extend(block)
    value = json.loads(response)
    if not isinstance(value, Mapping):
        raise ProtocolError("control_response_invalid")
    return value


async def serve(config: AgentConfig, slot_index: int) -> int:
    server = AgentServer(config, slot_index)
    loop = asyncio.get_running_loop()
    for name in (signal.SIGTERM, signal.SIGINT):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(name, server.stopping.set)
    await server.run()
    return 0


@dataclass
class TextSession:
    session_id: str
    state: ConversationState
    policy: dict[str, Any]
    recording_mode: str
    request_id: str
    lock: threading.RLock = field(default_factory=threading.RLock)
    records: list[dict[str, Any]] = field(default_factory=list)
    recorded_order_ids: set[str] = field(default_factory=set)
    terminal: bool = False


def synthetic_call_policy(within_phone_hours: bool) -> dict[str, Any]:
    empty_schedule = [
        {"weekday": weekday, "windows": []} for weekday in range(1, 8)
    ]
    return {
        "protocol": "kienzlefon-ai-call-policy-v1",
        "evaluated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "valid_for_ms": 1000,
        "timezone": "Europe/Berlin",
        "practice_open": within_phone_hours,
        "phone_open": within_phone_hours,
        "greeting_open": within_phone_hours,
        "urgent_help_active": False,
        "override_active": False,
        "override_blocks_phone_hours": False,
        "practice_queue_allowed": within_phone_hours,
        "pharmacy_transfer_allowed": True,
        "specialist_transfer_allowed": True,
        "opening_hours": list(empty_schedule),
        "phone_hours": list(empty_schedule),
        "spoken_information": {
            "opening_hours": "Für diesen Texttest sind keine Öffnungszeiten hinterlegt.",
            "phone_hours": "Für diesen Texttest sind keine Telefonzeiten hinterlegt.",
        },
        "dtmf": {"mode": "classic_handoff", "digits": list("0123456789*#")},
    }


class TextDebugHub:
    def __init__(self, config: AgentConfig) -> None:
        self.config = config
        self.lock = threading.RLock()
        self.subscribers: dict[int, TextDebugSubscriber] = {}
        self.next_subscriber = 1
        self.sequence = 0

    def _event(
        self, event: str, values: Mapping[str, Any] | None = None
    ) -> dict[str, Any]:
        if not IDENTIFIER_RE.fullmatch(event):
            raise AgentError("text_debug_event_name_invalid")
        values = values or {}
        if any(key in SENSITIVE_DEBUG_KEYS for key in values):
            raise AgentError("text_sensitive_debug_field_in_public_event")
        self.sequence += 1
        return {
            "protocol": DEBUG_PROTOCOL,
            "sequence": self.sequence,
            "epoch_ms": time.time_ns() // 1_000_000,
            "monotonic_ms": time.monotonic_ns() // 1_000_000,
            "slot_id": "chat",
            "event": event,
            **dict(values),
        }

    def emit(
        self,
        event: str,
        values: Mapping[str, Any] | None = None,
        sensitive: Mapping[str, Any] | None = None,
    ) -> None:
        try:
            with self.lock:
                public_event = self._event(event, values)
                if sensitive is not None and any(
                    key not in {
                        "text", "reply", "raw_response", "normalized_response"
                    }
                    for key in sensitive
                ):
                    raise AgentError("text_sensitive_debug_field_invalid")
                for subscriber_id, subscriber in tuple(self.subscribers.items()):
                    try:
                        item = dict(public_event)
                        if sensitive and subscriber.show_text:
                            item.update(sensitive)
                            item["sensitive"] = True
                        if subscriber.events.full():
                            with contextlib.suppress(queue.Empty):
                                subscriber.events.get_nowait()
                            subscriber.dropped += 1
                        if subscriber.dropped:
                            item["dropped_before"] = subscriber.dropped
                            subscriber.dropped = 0
                        subscriber.events.put_nowait(item)
                    except Exception:
                        self.subscribers.pop(subscriber_id, None)
        except Exception as error:
            LOGGER.warning(
                "event=text_debug_event_rejected code=%s",
                diagnostic_error_code(error),
            )

    def subscribe(self, requested: bool, peer_is_root: bool) -> tuple[int, TextDebugSubscriber]:
        if not isinstance(requested, bool):
            raise ProtocolError("text_debug_show_text_invalid")
        with self.lock:
            if len(self.subscribers) >= MAX_TEXT_DEBUG_SUBSCRIBERS:
                raise ProtocolError("text_debug_subscriber_limit")
            show_text = bool(
                requested
                and peer_is_root
                and self.config.debug_allow_sensitive_console
            )
            subscriber_id = self.next_subscriber
            self.next_subscriber += 1
            subscriber = TextDebugSubscriber(
                queue.Queue(maxsize=256), show_text
            )
            self.subscribers[subscriber_id] = subscriber
            return subscriber_id, subscriber

    def unsubscribe(self, subscriber_id: int) -> None:
        with self.lock:
            self.subscribers.pop(subscriber_id, None)

    def status_event(self) -> dict[str, Any]:
        with self.lock:
            return self._event("chat_status", {"state": "available"})


@dataclass
class TextDebugSubscriber:
    events: queue.Queue[dict[str, Any]]
    show_text: bool
    dropped: int = 0


class TextRuntime:
    def __init__(
        self,
        config: AgentConfig,
        debug: TextDebugHub | None = None,
    ) -> None:
        self.config = config
        self.debug = debug
        self.lock = threading.RLock()
        self.sessions: dict[str, TextSession] = {}

    def emit_debug(
        self,
        event: str,
        values: Mapping[str, Any] | None = None,
        sensitive: Mapping[str, Any] | None = None,
    ) -> None:
        if self.debug is not None:
            self.debug.emit(event, values, sensitive)

    def metadata(self) -> dict[str, Any]:
        overlay_hashes = {
            "telephone": hashlib.sha256(
                self.config.telephone_overlay.encode()
            ).hexdigest(),
            "chat": hashlib.sha256(self.config.chat_overlay.encode()).hexdigest(),
        }
        return {
            "protocol": "kienzlefon-ai-text-v1",
            "backend_version": VERSION,
            "system_prompt": self.config.system_prompt,
            "system_prompt_sha256": hashlib.sha256(
                self.config.system_prompt.encode()
            ).hexdigest(),
            "channel_overlays": {
                "telephone": self.config.telephone_overlay,
                "chat": self.config.chat_overlay,
            },
            "channel_overlay_sha256": overlay_hashes,
            "llm_url": self.config.llm_url,
            "recording_modes": ["ephemeral", "spool"],
            "inference": {
                "max_tokens": self.config.max_llm_tokens,
                "temperature": self.config.temperature,
                "enable_thinking": False,
            },
        }

    def create_session(self, body: Mapping[str, Any]) -> dict[str, Any]:
        channel = body.get("channel")
        if channel not in ALLOWED_CHANNELS:
            raise ProtocolError("text_channel_invalid")
        recording_mode = body.get("recording_mode", "ephemeral")
        if recording_mode not in {"ephemeral", "spool"}:
            raise ProtocolError("text_recording_mode_invalid")
        if recording_mode == "spool" and channel != "chat":
            raise ProtocolError("text_spool_channel_invalid")
        caller_id = _safe_caller(body.get("caller_id"))
        environment = body.get("environment", {})
        if not isinstance(environment, Mapping):
            raise ProtocolError("text_environment_invalid")
        within_phone_hours = environment.get(
            "within_phone_hours", body.get("within_phone_hours", False)
        )
        if not isinstance(within_phone_hours, bool):
            raise ProtocolError("text_phone_hours_invalid")
        supplied_policy = body.get("call_policy")
        policy = (
            validate_call_policy(supplied_policy)
            if supplied_policy is not None
            else synthetic_call_policy(within_phone_hours)
        )
        session_id = str(uuid.uuid4())
        request_id = f"text-chat-{session_id}"
        session = TextSession(
            session_id,
            ConversationState(channel=channel, caller_id=caller_id),
            policy,
            str(recording_mode),
            request_id,
        )
        with self.lock:
            if len(self.sessions) >= MAX_TEXT_SESSIONS:
                raise ProtocolError("text_session_limit")
            self.sessions[session_id] = session
        self.emit_debug(
            "chat_session_started",
            {"recording_mode": recording_mode},
        )
        return {
            "protocol": "kienzlefon-ai-text-v1",
            "session_id": session_id,
            "channel": channel,
            "recording_mode": recording_mode,
            "introduction_already_handled": True,
            "terminal": False,
        }

    def get_session(self, session_id: str) -> TextSession:
        try:
            uuid.UUID(session_id)
        except ValueError as exc:
            raise ProtocolError("text_session_id_invalid") from exc
        with self.lock:
            session = self.sessions.get(session_id)
        if session is None:
            raise ProtocolError("text_session_not_found")
        return session

    def finalize(self, session: TextSession) -> None:
        prepare_lossless_terminal_orders(session.state)
        for order in session.state.orders:
            if (
                not order.complete
                or order.order_id in session.recorded_order_ids
                or order.committed
            ):
                continue
            if session.recording_mode == "spool":
                started = time.monotonic()
                try:
                    call_id = commit_order(
                        self.config,
                        session.request_id,
                        session.state.caller_id,
                        order,
                    )
                except Exception as error:
                    self.emit_debug(
                        "chat_order_commit_error",
                        {
                            "order_id": order.order_id,
                            "call_type": order.call_type,
                            "code": diagnostic_error_code(error),
                        },
                    )
                    raise
                order.committed = True
                order.call_id = call_id
                session.records.append(
                    {
                        "order_id": order.order_id,
                        "type": order.call_type,
                        "complete": True,
                        "data": dict(order.fields),
                        "zusammenfassung": order.zusammenfassung,
                        "adapter": "kienzlefon_spool",
                        "call_id": call_id,
                    }
                )
                self.emit_debug(
                    "chat_order_commit_end",
                    {
                        "order_id": order.order_id,
                        "call_type": order.call_type,
                        "call_id": call_id,
                        "duration_ms": round((time.monotonic() - started) * 1000),
                    },
                )
            else:
                session.records.append(
                    {
                        "order_id": order.order_id,
                        "type": order.call_type,
                        "complete": True,
                        "data": dict(order.fields),
                        "zusammenfassung": order.zusammenfassung,
                        "adapter": "text_recording",
                    }
                )
            session.recorded_order_ids.add(order.order_id)

    @staticmethod
    def response_payload(
        session: TextSession,
        result: LLMResult | None,
        action_result: Mapping[str, Any] | None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "protocol": "kienzlefon-ai-text-v1",
            "session_id": session.session_id,
            "channel": session.state.channel,
            "recording_mode": session.recording_mode,
            "terminal": session.terminal,
            "state": {
                "action": session.state.action,
                "orders": [
                    order_payload(order, include_internal=True)
                    for order in session.state.orders
                ],
            },
            "records": list(session.records),
            "action_result": dict(action_result) if action_result else None,
        }
        if result is not None:
            payload.update(
                {
                    "reply": result.reply,
                    "raw_response": result.raw,
                    "normalized_response": {
                        "reply": result.reply,
                        "action": result.action,
                        "orders": [order_payload(order) for order in result.orders],
                    },
                    "repairs": list(result.repairs),
                }
            )
        return payload

    def turn(self, session_id: str, body: Mapping[str, Any]) -> dict[str, Any]:
        session = self.get_session(session_id)
        text = body.get("text")
        if (
            not isinstance(text, str)
            or not text.strip()
            or len(text) > TRANSCRIPT_LIMIT
            or "\x00" in text
        ):
            raise ProtocolError("text_turn_invalid")
        with session.lock:
            if session.terminal:
                raise ProtocolError("text_session_terminal")
            clean_text = text.strip()
            started = time.monotonic()
            self.emit_debug(
                "chat_llm_start",
                {
                    "input_chars": len(clean_text),
                    "recording_mode": session.recording_mode,
                },
                {"text": clean_text},
            )
            try:
                result = call_llm(
                    self.config, session.state, clean_text, session.policy
                )
            except Exception as error:
                self.emit_debug(
                    "chat_llm_error",
                    {
                        "duration_ms": round((time.monotonic() - started) * 1000),
                        "code": diagnostic_error_code(error),
                    },
                )
                raise
            self.emit_debug(
                "chat_llm_end",
                {
                    "duration_ms": round((time.monotonic() - started) * 1000),
                    "reply_chars": len(result.reply),
                    "order_count": len(result.orders),
                    "complete_order_count": sum(
                        order.complete for order in result.orders
                    ),
                    "action": result.action,
                    "repair_count": len(result.repairs),
                    "recording_mode": session.recording_mode,
                },
                {
                    "reply": result.reply,
                    "raw_response": result.raw,
                    "normalized_response": {
                        "reply": result.reply,
                        "action": result.action,
                        "orders": [order_payload(order) for order in result.orders],
                    },
                },
            )
            apply_llm_result(session.state, result, clean_text)
            action_result: Mapping[str, Any] | None = None
            if result.action == "beenden":
                self.finalize(session)
                session.terminal = True
                action_result = {
                    "action": "beenden",
                    "requested": True,
                    "executed": True,
                    "reason": "conversation_ended",
                }
            elif result.action in ACTION_TARGETS:
                protected_handoff_record = any(
                    marker in result.repairs
                    for marker in (
                        "role_route_patient_emergency",
                        "role_route_professional_urgent",
                        "role_route_professional_urgent_outside_hours",
                        "role_route_care_service",
                        "role_route_care_service_outside_hours",
                        "au_handoff",
                    )
                )

                if protected_handoff_record:
                    self.finalize(session)

                session.terminal = True
                action_result = {
                    "action": result.action,
                    "handoff_target": ACTION_TARGETS[result.action],
                    "requested": True,
                    "executed": False,
                    "reason": "text_transport_no_handoff",
                }
            return self.response_payload(session, result, action_result)

    def hangup(self, session_id: str) -> dict[str, Any]:
        session = self.get_session(session_id)
        with session.lock:
            if not session.terminal:
                self.finalize(session)
                session.terminal = True
                session.state.action = "beenden"
            self.emit_debug(
                "chat_session_hangup",
                {
                    "recording_mode": session.recording_mode,
                    "record_count": len(session.records),
                },
            )
            return self.response_payload(
                session,
                None,
                {
                    "action": "hangup",
                    "requested": True,
                    "executed": True,
                    "reason": "simulated_transport_end",
                },
            )

    def delete(self, session_id: str) -> None:
        session = self.get_session(session_id)
        with session.lock:
            if not session.terminal:
                raise ProtocolError("text_session_not_terminal")
        with self.lock:
            self.sessions.pop(session_id, None)
        self.emit_debug(
            "chat_session_deleted",
            {
                "recording_mode": session.recording_mode,
                "record_count": len(session.records),
            },
        )


class TextDebugHandler(socketserver.StreamRequestHandler):
    server: "TextDebugServer"

    @staticmethod
    def peer_uid(connection: socket.socket) -> int | None:
        if not hasattr(socket, "SO_PEERCRED"):
            return None
        try:
            size = struct.calcsize("3i")
            credentials = connection.getsockopt(
                socket.SOL_SOCKET, socket.SO_PEERCRED, size
            )
            _pid, uid, _gid = struct.unpack("3i", credentials)
            return int(uid)
        except OSError:
            return None

    def send_json(self, value: Mapping[str, Any]) -> None:
        self.wfile.write(
            json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
            + b"\n"
        )
        self.wfile.flush()

    def handle(self) -> None:
        subscriber_id: int | None = None
        try:
            raw = self.rfile.readline(MAX_CONTROL_RESPONSE_BYTES + 1)
            if (
                not raw.endswith(b"\n")
                or len(raw) > MAX_CONTROL_RESPONSE_BYTES
            ):
                raise ProtocolError("text_debug_request_invalid")
            message = json.loads(raw)
            if (
                not isinstance(message, Mapping)
                or message.get("command") != "debug_subscribe"
            ):
                raise ProtocolError("text_debug_command_invalid")
            subscriber_id, subscriber = self.server.hub.subscribe(
                message.get("show_text", False),
                self.peer_uid(self.request) == 0,
            )
            self.send_json(
                {
                    "ok": True,
                    "protocol": DEBUG_PROTOCOL,
                    "source": "chat",
                    "show_text": subscriber.show_text,
                    "sensitive_console_allowed": bool(
                        self.server.hub.config.debug_allow_sensitive_console
                        and self.peer_uid(self.request) == 0
                    ),
                }
            )
            self.send_json(self.server.hub.status_event())
            while not self.server.stopping.is_set():
                try:
                    event = subscriber.events.get(timeout=1.0)
                except queue.Empty:
                    continue
                self.send_json(event)
        except (
            BrokenPipeError,
            ConnectionError,
            OSError,
            json.JSONDecodeError,
            AgentError,
        ):
            return
        finally:
            if subscriber_id is not None:
                self.server.hub.unsubscribe(subscriber_id)


class TextDebugServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def __init__(self, path: str, hub: TextDebugHub) -> None:
        self.hub = hub
        self.stopping = threading.Event()
        super().__init__(path, TextDebugHandler)


class TextAPIHandler(BaseHTTPRequestHandler):
    server: "TextAPIServer"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def send_json(self, status: int, value: Mapping[str, Any]) -> None:
        body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def read_json(self) -> Mapping[str, Any]:
        raw_length = self.headers.get("Content-Length", "")
        if not raw_length.isdigit():
            raise ProtocolError("text_content_length_invalid")
        length = int(raw_length)
        if not 0 <= length <= MAX_TEXT_REQUEST_BYTES:
            raise ProtocolError("text_request_too_large")
        body = self.rfile.read(length)
        value = json.loads(body or b"{}")
        if not isinstance(value, Mapping):
            raise ProtocolError("text_request_invalid")
        return value

    def dispatch(self) -> None:
        if self.command == "GET" and self.path == "/health":
            self.send_json(200, {"ok": True, "version": VERSION})
            return
        if self.command == "GET" and self.path == "/v1/dialog/metadata":
            self.send_json(200, self.server.runtime.metadata())
            return
        if self.command == "POST" and self.path == "/v1/dialog/sessions":
            self.send_json(201, self.server.runtime.create_session(self.read_json()))
            return
        match = re.fullmatch(
            r"/v1/dialog/sessions/([0-9a-fA-F-]{36})(?:/(turn|hangup))?",
            self.path,
        )
        if match and self.command == "POST" and match.group(2) == "turn":
            self.send_json(
                200, self.server.runtime.turn(match.group(1), self.read_json())
            )
            return
        if match and self.command == "POST" and match.group(2) == "hangup":
            self.read_json()
            self.send_json(200, self.server.runtime.hangup(match.group(1)))
            return
        if match and self.command == "DELETE" and match.group(2) is None:
            self.server.runtime.delete(match.group(1))
            self.send_json(200, {"ok": True})
            return
        self.send_json(404, {"ok": False, "reason": "not_found"})

    def do_GET(self) -> None:
        try:
            self.dispatch()
        except Exception:
            self.send_json(400, {"ok": False, "reason": "rejected"})

    def do_POST(self) -> None:
        try:
            self.dispatch()
        except Exception:
            self.send_json(400, {"ok": False, "reason": "rejected"})

    def do_DELETE(self) -> None:
        try:
            self.dispatch()
        except Exception:
            self.send_json(400, {"ok": False, "reason": "rejected"})


class TextAPIServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, config: AgentConfig, debug: TextDebugHub) -> None:
        self.runtime = TextRuntime(config, debug)
        super().__init__((config.text_api_bind, config.text_api_port), TextAPIHandler)


def serve_text(config: AgentConfig) -> int:
    if not config.text_api_enabled:
        raise AgentError("text_api_disabled")
    debug = TextDebugHub(config)
    server = TextAPIServer(config, debug)
    debug_path = config.runtime_directory / "text" / "control.sock"
    debug_path.parent.mkdir(parents=True, exist_ok=True)
    debug_path.unlink(missing_ok=True)
    debug_server = TextDebugServer(str(debug_path), debug)
    os.chmod(debug_path, 0o600)
    debug_thread = threading.Thread(
        target=debug_server.serve_forever,
        kwargs={"poll_interval": 0.25},
        daemon=True,
    )
    debug_thread.start()

    def stop(_signum: int, _frame: Any) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()
        debug_server.stopping.set()
        threading.Thread(target=debug_server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    LOGGER.info(
        "event=text_api_started bind=127.0.0.1 port=%d debug_socket=%s",
        config.text_api_port,
        debug_path,
    )
    try:
        server.serve_forever(poll_interval=0.25)
    finally:
        debug_server.stopping.set()
        debug_server.shutdown()
        debug_server.server_close()
        debug_thread.join(timeout=5)
        debug_path.unlink(missing_ok=True)
        server.server_close()
    return 0


async def configurable_filler_self_test() -> None:
    from types import SimpleNamespace
    from unittest.mock import patch
    defaults = filler_options({})
    assert defaults["filler_start_ms"] == (2000, 7000, 13000)
    for raw in ({"part1_text": 42}, {"part1_text": "x\ny"}, {"part1_text": "x" * 241},
                {"part2_start_ms": 1}, {"part1_start_ms": -1}, {"part1_start_ms": True},
                {"part3_start_ms": 120001}, {"beep_frequency_hz": 0},
                {"beep_volume": float("nan")}, {"beep_volume": True}, {"beep_volume": 0.6},
                {"beep_interval_ms": 0}, {"beep_duration_ms": 21},
                {"beep_interval_ms": 200, "beep_duration_ms": 220},
                {"regenerate_on_reload": "true"}, {"beep_enabled": 1}):
        try:
            filler_options(raw)
        except AgentError:
            pass
        else:
            raise AssertionError("invalid feedback configuration accepted")
    assert filler_options({"part1_text": "  "})["filler_texts"][0] == ""
    config = SimpleNamespace(**defaults)
    beep = make_filler_beep(config)
    values = struct.unpack("<" + "h" * (len(beep) // 2), beep)
    assert len(beep) == TELEPHONY_FRAME_BYTES * 5 and values[0] == values[-1] == 0
    assert 0 < max(values) <= math.ceil(32767 * 0.15)
    # Count rising zero crossings away from the two ramps: 400 Hz for 80 ms.
    middle = values[160:-160]
    assert 30 <= sum(a <= 0 < b for a, b in zip(middle, middle[1:])) <= 33
    assert make_filler_beep(SimpleNamespace(**{**defaults, "filler_beep_enabled": False})) == b""

    @dataclass(frozen=True)
    class Voice:
        qwen_speaker: str = "uncle_fu"
        qwen_language: str = "German"
        qwen_seed: int = 42
        filler_seed: int = 12345
        filler_texts: tuple[str, ...] = FILLER_TEXTS

    def pcm(value: int, frames: int = 3) -> bytes:
        return struct.pack("<h", value) * (TELEPHONY_FRAME_BYTES // 2) * frames
    voice = Voice()
    generated: list[str] = []
    def synth(config: Any, text: str, backend: str, emit: Any) -> None:
        assert config.qwen_seed == 12345 and backend == "qwen"
        generated.append(text)
        emit(pcm(300))
    with tempfile.TemporaryDirectory(prefix="filler-2.5.1-assets-") as directory:
        root = Path(directory)
        legacy = root / "legacy"
        legacy.mkdir()
        old = {"profile": filler_profile(voice), "sample_rate": TELEPHONY_RATE,
               "encoding": "pcm_s16le", "channels": 1, "clips": {}}
        for name, value in zip(FILLER_FILES, (100, 200, 100)):
            (legacy / name).write_bytes(pcm(value))
            old["clips"][name] = hashlib.sha256(pcm(value)).hexdigest()
        (legacy / "manifest.json").write_text(json.dumps(old))
        with patch.dict(globals(), stream_tts=synth):
            prepare_filler_clips(voice, root / "import", legacy)
            assert not generated and load_filler_clips(voice, root / "import") == (pcm(100), pcm(200), pcm(100))
            changed = replace(voice, filler_texts=("Neuer statischer Test.", FILLER_TEXTS[1], FILLER_TEXTS[2]))
            prepare_filler_clips(changed, root / "changed", legacy)
            assert generated == ["Neuer statischer Test."]
            assert load_filler_clips(changed, root / "changed") == (pcm(300), pcm(200), pcm(100))
            prepare_filler_clips(replace(changed, qwen_seed=999), root / "reused", root / "changed")
            assert len(generated) == 1
            disabled = replace(voice, filler_texts=("", "", ""))
            prepare_filler_clips(disabled, root / "disabled", root / "changed")
            assert load_filler_clips(disabled, root / "disabled") == (b"", b"", b"")
            assert len(generated) == 1
            # Reordering identical content only reuses bytes; it does not synthesize.
            reordered = replace(voice, filler_texts=(FILLER_TEXTS[1], "", FILLER_TEXTS[0]))
            prepare_filler_clips(reordered, root / "reordered", root / "import")
            assert load_filler_clips(reordered, root / "reordered") == (pcm(200), b"", pcm(100))
            assert len(generated) == 1
            (root / "changed" / FILLER_FILES[0]).write_bytes(b"corrupt")
            prepare_filler_clips(changed, root / "repaired", root / "changed")
            assert len(generated) == 2
            (legacy / FILLER_FILES[0]).unlink()
            (legacy / FILLER_FILES[0]).symlink_to(root / "import" / FILLER_FILES[0])
            try:
                load_filler_clips(voice, legacy)
            except AgentError:
                pass
            else:
                raise AssertionError("symlink clip accepted")
        # A generation failure must not alter the reusable source set.
        before = {p.name: p.read_bytes() for p in (root / "import").iterdir()}
        with patch.dict(globals(), stream_tts=lambda *_: (_ for _ in ()).throw(RuntimeError("synthetic"))):
            try:
                prepare_filler_clips(changed, root / "failed", root / "import")
            except RuntimeError:
                pass
            else:
                raise AssertionError("generation failure ignored")
        assert before == {p.name: p.read_bytes() for p in (root / "import").iterdir()}

    class Writer:
        def __init__(self) -> None:
            self.frames: list[tuple[float, int]] = []
        def write(self, data: bytes) -> None:
            assert data[0] == AUDIO_TYPE_SLIN16 and len(data) == TELEPHONY_FRAME_BYTES + 3
            self.frames.append((time.monotonic(), struct.unpack("<h", data[3:5])[0]))
        async def drain(self) -> None:
            await asyncio.sleep(0)
    def metrics() -> TurnPerformance:
        now = time.monotonic_ns()
        return TurnPerformance(1, UtteranceResult(pcm(20), 500, 1000, 500, "silence", now, now - 500_000_000))
    async def eventually(predicate: Callable[[], bool]) -> None:
        async with asyncio.timeout(3):
            while not predicate():
                await asyncio.sleep(0.001)
    async def scheduled() -> None:
        writer, turn = Writer(), metrics()
        settings = SimpleNamespace(**{**defaults, "filler_start_ms": (420, 1020, 1620),
                                     "filler_beep_interval_ms": 200})
        playback = FillerPlayback((pcm(100), pcm(200), pcm(300)), writer, asyncio.Lock(),
                                  asyncio.Event(), turn, settings, pcm(900, 2))
        await eventually(lambda: turn.filler_blocks_completed == 3 and turn.beep_count >= 7)
        await playback.release_to_reply()
        frames = writer.frames
        origin = turn.utterance.endpoint_detected_monotonic_ns / 1e9
        for value, start_ms in ((100, 420), (200, 1020), (300, 1620)):
            selected = [(stamp, v) for stamp, v in frames if v == value]
            assert len(selected) == 3 and selected[0][0] - origin >= start_ms / 1000
            indices = [i for i, (_, v) in enumerate(frames) if v == value]
            assert indices == list(range(indices[0], indices[0] + 3))
        assert [v for _, v in frames[:4]] == [900] * 4  # two tones before part one
        assert frames[2][0] - frames[0][0] >= 0.18
        assert turn.filler_audio_ms == 180 and turn.beep_audio_ms == turn.beep_count * 40
        assert turn.end_of_detected_speech_to_first_beep_audio_ms < 100
        assert turn.end_of_detected_speech_to_first_filler_audio_ms >= 420
        assert turn.end_of_detected_speech_to_first_reply_audio_ms is None
        count = len(frames)
        await asyncio.sleep(0.05)
        assert len(frames) == count
        await playback.close()
    await asyncio.gather(*(scheduled() for _ in range(3)))
    # Overlapping deadlines serialize speech; an empty middle part is skipped.
    writer, turn = Writer(), metrics()
    settings = SimpleNamespace(**{**defaults, "filler_start_ms": (0, 0, 20)})
    playback = FillerPlayback((pcm(100), b"", pcm(300)), writer, asyncio.Lock(), asyncio.Event(), turn, settings)
    await asyncio.wait_for(playback.task, 1)
    assert [v for _, v in writer.frames] == [100] * 3 + [300] * 3
    await playback.close()
    # Reply before any output; reply in tone; hangup in endless tones after all speech.
    for mode in ("before", "tone", "hangup"):
        writer, turn, active = Writer(), metrics(), asyncio.Event()
        playback = FillerPlayback((), writer, asyncio.Lock(), active, turn, config, pcm(900, 2))
        if mode != "before":
            await eventually(lambda: bool(writer.frames))
        if mode == "hangup":
            await playback.close()
        else:
            await playback.release_to_reply()
        count = len(writer.frames)
        await asyncio.sleep(0.06)
        assert len(writer.frames) == count and not active.is_set()
        assert turn.filler_blocks_started == 0
        assert turn.beep_count == (0 if mode == "before" else 1)
        await playback.close()
    print("configurable filler text/cache/timeline/beep/reply/parallel self-test: ok")


async def filler_self_test() -> None:
    """Synthetic PCM only: no service, GPU, network or conversation recording."""
    import dataclasses
    from types import SimpleNamespace
    from unittest.mock import patch

    async def eventually(predicate: Callable[[], bool]) -> None:
        async with asyncio.timeout(3):
            while not predicate():
                await asyncio.sleep(0.001)

    def clip(value: int, frames: int = 3) -> bytes:
        return struct.pack("<h", value) * (TELEPHONY_FRAME_BYTES // 2) * frames

    assert FILLER_TEXTS == ("Bitte warten.", "Ich verarbeite.", "Bitte warten.")
    clips = tuple(clip(value) for value in (100, 200, 100))
    @dataclasses.dataclass
    class FillerVoice:
        qwen_speaker: str = "uncle_fu"
        qwen_language: str = "German"
        qwen_seed: int = 42
        filler_seed: int = 12345

    voice = FillerVoice()
    prepared: list[str] = []

    def prepare(_config: Any, text: str, backend: str, emit: Any) -> None:
        assert backend == "qwen" and text in FILLER_TEXTS
        assert _config is not voice
        assert _config.qwen_seed == voice.filler_seed
        prepared.append(text)
        emit(clips[FILLER_TEXTS.index(text)])

    with tempfile.TemporaryDirectory(prefix="kienzlefon-filler-test-") as temporary:
        root = Path(temporary)
        with patch.dict(globals(), stream_tts=prepare):
            prepare_filler_clips(voice, root / "first", root / "absent")
            assert prepared == ["Bitte warten.", "Ich verarbeite."]
            assert voice.qwen_seed == 42
            assert load_filler_clips(voice, root / "first") == clips
            assert (root / "first" / FILLER_FILES[0]).read_bytes() == (root / "first" / FILLER_FILES[2]).read_bytes()
            prepare_filler_clips(voice, root / "reused", root / "first")
            assert len(prepared) == 2
            voice.qwen_seed = 43
            assert load_filler_clips(voice, root / "first") == clips
            prepare_filler_clips(voice, root / "live-seed-changed", root / "first")
            assert len(prepared) == 2
            voice.filler_seed = 54321
            prepare_filler_clips(voice, root / "changed", root / "first")
            assert len(prepared) == 4
            assert voice.qwen_seed == 43
            voice.filler_seed = 12345
            voice.qwen_seed = 42
            # A valid 2.4 manifest must not reuse the old wording after update.
            old_texts = ("Gerne.", "Einen kleinen Moment bitte.", "Ich prüfe das kurz für Sie.")
            old_files = ("01-gerne.pcm", "02-moment.pcm", "03-pruefen.pcm")
            old_directory = root / "legacy-2.4"
            old_directory.mkdir()
            manifest = json.loads((root / "first" / "manifest.json").read_text(encoding="ascii"))
            manifest.pop("schema_version", None)
            manifest["clips"] = {}
            for name, pcm in zip(old_files, clips):
                (old_directory / name).write_bytes(pcm)
                manifest["clips"][name] = hashlib.sha256(pcm).hexdigest()
            with patch.dict(globals(), FILLER_TEXTS=old_texts):
                old_profile = filler_profile(voice)
            assert old_profile != filler_profile(voice)
            manifest["profile"] = old_profile
            old_manifest = json.dumps(manifest)
            (old_directory / "manifest.json").write_text(old_manifest, encoding="ascii")
            with patch.dict(globals(), FILLER_TEXTS=old_texts, FILLER_FILES=old_files):
                assert load_filler_clips(voice, old_directory) == clips
            prepare_filler_clips(voice, root / "upgraded", old_directory)
            assert len(prepared) == 6
            assert load_filler_clips(voice, root / "upgraded") == clips
            assert (old_directory / "manifest.json").read_text(encoding="ascii") == old_manifest
            assert tuple((old_directory / name).read_bytes() for name in old_files) == clips
        path = root / "first" / FILLER_FILES[0]
        path.write_bytes(clip(999))
        try:
            load_filler_clips(voice, root / "first")
        except ProtocolError:
            pass
        else:
            raise AssertionError("accepted corrupted filler")
        path.unlink()
        try:
            load_filler_clips(voice, root / "first")
        except (OSError, ProtocolError):
            pass
        else:
            raise AssertionError("accepted missing filler")

    class Writer:
        def __init__(self) -> None:
            self.frames: list[tuple[float, int]] = []

        def write(self, data: bytes) -> None:
            if data[0] == AUDIO_TYPE_SLIN16:
                assert len(data) == TELEPHONY_FRAME_BYTES + 3
                self.frames.append((time.monotonic(), struct.unpack("<h", data[3:5])[0]))

        async def drain(self) -> None:
            await asyncio.sleep(0)

    def metrics() -> TurnPerformance:
        now = time.monotonic_ns()
        return TurnPerformance(1, UtteranceResult(
            clip(2000), 1000, 1500, 500, "silence", now, now - 500_000_000))

    async def boundary(block: int, gap: bool = False) -> None:
        writer, values, active = Writer(), metrics(), asyncio.Event()
        playback = FillerPlayback(clips, writer, asyncio.Lock(), active, values)
        if block:
            await eventually(lambda: (values.filler_blocks_completed if gap
                                      else values.filler_blocks_started) >= block)
        await playback.release_to_reply()
        assert values.filler_blocks_started == values.filler_blocks_completed == block
        assert [value for _, value in writer.frames] == [100, 100, 100, 200, 200, 200, 100, 100, 100][:block * 3]
        assert values.filler_audio_ms == block * 60 and not active.is_set()
        assert values.tts_first_audio_written_ms is None
        if block:
            assert values.end_of_actual_speech_to_first_filler_audio_ms >= 500
        await playback.close()

    with patch.object(FillerPlayback, "GAP_SECONDS", 0.03):
        for block in range(4):
            await boundary(block)
        await boundary(1, gap=True)
        await boundary(2, gap=True)
        await asyncio.gather(*(boundary(3) for _ in range(3)))
        writer, values, active = Writer(), metrics(), asyncio.Event()
        playback = FillerPlayback(clips, writer, asyncio.Lock(), active, values)
        await eventually(lambda: bool(writer.frames))
        await playback.close()
        count = len(writer.frames)
        await asyncio.sleep(0.04)
        assert len(writer.frames) == count and not active.is_set()

    # Real one-second gaps, measured from the end of the previous PCM block.
    writer, values = Writer(), metrics()
    playback = FillerPlayback(clips, writer, asyncio.Lock(), asyncio.Event(), values)
    await asyncio.wait_for(playback.task, 3)
    assert values.filler_blocks_completed == 3 and len(writer.frames) == 9
    assert [value for _, value in writer.frames] == [100, 100, 100, 200, 200, 200, 100, 100, 100]
    assert writer.frames[3][0] - writer.frames[2][0] >= 0.97
    assert writer.frames[6][0] - writer.frames[5][0] >= 0.97
    await playback.close()

    # Real run_call/speak paths; service gates allow deterministic hangups at
    # ASR, LLM and TTS and ensure filler continues until actual PCM exists.
    async def call_path(mode: str) -> None:
        config = SimpleNamespace(
            slot_count=3, slot_id=lambda index: f"ai-slot-{index:02d}",
            streaming_asr=False, speculative_llm=False, filler_enabled=mode != "disabled",
            filler_start_ms=(0, 140 if mode == "normal_beep" else 90, 600), filler_beep_enabled=mode == "normal_beep",
            filler_beep_start_ms=70, filler_beep_interval_ms=200,
            filler_beep_frequency_hz=400, filler_beep_duration_ms=20, filler_beep_volume=0.15,
            max_turns=1, greeting="synthetic greeting", technical_failure="synthetic failure",
            tts_backend="qwen", energy_threshold=520, preroll_ms=300,
            speech_start_ms=120, speech_end_ms=500, debug_allow_sensitive_console=False,
            performance_enabled=False, performance_log_file=MANAGED_PERFORMANCE_LOG,
            performance_max_bytes=10485760, performance_backup_count=5,
        )
        hangup, asr_started, asr_release = asyncio.Event(), asyncio.Event(), asyncio.Event()
        llm_started, llm_release = asyncio.Event(), asyncio.Event()
        commit_started, commit_release = asyncio.Event(), asyncio.Event()
        tts_started, tts_release = threading.Event(), threading.Event()
        records: list[dict[str, Any]] = []
        calls: list[str] = []
        writer = Writer()

        class Server(AgentServer):
            def emit_debug(self, *_args: Any, **_kwargs: Any) -> None:
                pass

            async def audio_reader(self, _reader: Any, incoming: Any, *_args: Any) -> None:
                await hangup.wait()
                await incoming.put(None)

            async def next_utterance(self, _queue: Any, session: Any = None) -> UtteranceResult | None:
                if mode == "empty" and asr_started.is_set():
                    return None
                assert session is None and not asr_started.is_set() and not llm_started.is_set()
                assert not any(value in (100, 200, 300) for _, value in writer.frames)
                return metrics().utterance

            async def get_call_policy(self, _claim: Any) -> dict[str, Any]:
                return {}

            async def commit_completed_orders(self, *_args: Any) -> int:
                if mode == "hangup_commit":
                    commit_started.set()
                    await commit_release.wait()
                return 0

        async def asr(_config: Any, pcm: bytes, _debug: Any) -> ASRResult:
            assert pcm == clip(2000)
            calls.append("asr")
            asr_started.set()
            await asr_release.wait()
            if mode == "error":
                raise ProtocolError("asr_finalization_timeout")
            if mode == "empty":
                raise ProtocolError("asr_empty_confirmed_transcript")
            return ASRResult("synthetic final", 1, 1, 0, 1)

        async def llm(_config: Any, _state: Any, transcript: str, _policy: Any) -> LLMResult:
            assert asr_release.is_set() and transcript == "synthetic final"
            calls.append("llm")
            llm_started.set()
            await llm_release.wait()
            return LLMResult("synthetic reply", "beenden", [], {})

        def tts(_config: Any, text: str, _backend: str, emit: Any, _notify: Any) -> None:
            assert text not in FILLER_TEXTS  # Never synthesize fillers during calls.
            calls.append(text)
            if text == "synthetic reply":
                tts_started.set()
                assert tts_release.wait(3)
                if mode == "error_tts":
                    raise RuntimeError("synthetic_tts_error")
                emit(clip(900))
            else:
                emit(clip(800, 1))

        def load(_config: Any) -> tuple[bytes, ...]:
            if mode == "missing":
                raise FileNotFoundError()
            return clips

        with patch.dict(globals(), load_filler_clips=load, batch_asr_transcribe=asr,
                        call_llm_async=llm, stream_tts=tts):
            server = Server(config, 0)
            server.performance.submit = records.append
            task = asyncio.create_task(server.run_call(SimpleNamespace(caller_id=""), None, writer))
            try:
                await eventually(asr_started.is_set)
                if mode not in {"missing", "disabled"}:
                    await eventually(lambda: any(value == 100 for _, value in writer.frames))
                assert not llm_started.is_set()
                if mode == "hangup_asr":
                    hangup.set()
                else:
                    asr_release.set()
                    if mode not in {"error", "empty"}:
                        await eventually(llm_started.is_set)
                        if mode == "hangup_llm":
                            hangup.set()
                        else:
                            llm_release.set()
                            if mode == "hangup_commit":
                                await eventually(commit_started.is_set)
                                hangup.set()
                                await asyncio.sleep(0.02)
                                count = sum(value in (100, 200, 300) for _, value in writer.frames)
                                await asyncio.sleep(0.06)
                                assert sum(value in (100, 200, 300) for _, value in writer.frames) == count
                                commit_release.set()
                            else:
                                await eventually(tts_started.is_set)
                                if mode not in {"missing", "disabled"}:
                                    await eventually(lambda: any(value == 200 for _, value in writer.frames))
                                if mode == "hangup_tts":
                                    hangup.set()
                                else:
                                    tts_release.set()
                await asyncio.wait_for(task, 3)
            finally:
                tts_release.set()
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
                server.performance.close()
        assert len(records) == 1, (mode, records)
        record = records[0]
        assert set(record) == PERFORMANCE_RECORD_KEYS
        assert record["pipeline_mode"] == ("half_duplex" if mode == "disabled" else "half_duplex_filler")
        response_frames = [(stamp, value) for stamp, value in writer.frames if value == 900]
        if mode.startswith("hangup"):
            assert record["outcome"] == "caller_hangup" and not response_frames
            if mode == "hangup_commit":
                assert "synthetic reply" not in calls
        elif mode in {"error", "error_tts"}:
            assert record["outcome"] == "failed" and not response_frames
            assert ("llm" in calls) is (mode == "error_tts")
            assert calls.count("synthetic failure") == 1
        elif mode == "empty":
            assert record["outcome"] == "asr_empty" and "llm" not in calls
            assert "synthetic failure" not in calls and not response_frames
        else:
            assert record["outcome"] == "completed", (mode, record)
            assert calls.count("asr") == calls.count("llm") == 1
            assert len(response_frames) == 3
            assert response_frames[-1][0] - response_frames[0][0] >= 0.035
            assert not any(value in (100, 200, 300) and stamp >= response_frames[0][0]
                           for stamp, value in writer.frames)
            if mode not in {"missing", "disabled"}:
                assert record["filler_blocks_started"] == record["filler_blocks_completed"] == 2
                assert record["end_of_actual_speech_to_first_reply_audio_ms"] > record["end_of_actual_speech_to_first_filler_audio_ms"]
                assert record["reply_audio_wait_for_filler_ms"] is not None
        if mode in {"missing", "disabled"}:
            assert record["filler_available"] == record["filler_blocks_started"] == 0
        if mode == "normal_beep":
            assert record["beep_count"] == 1 and record["beep_audio_ms"] == 20
            assert record["end_of_detected_speech_to_first_reply_audio_ms"] > record["end_of_detected_speech_to_first_beep_audio_ms"]
        await asyncio.sleep(0.02)  # let the cancelled synthetic TTS worker exit

    with patch.object(FillerPlayback, "GAP_SECONDS", 0.03):
        for mode in ("normal", "normal_beep", "missing", "disabled", "error", "error_tts", "empty",
                     "hangup_asr", "hangup_llm", "hangup_tts", "hangup_commit"):
            await call_path(mode)

    async def parallel_calls() -> None:
        words = ("alpha", "beta", "gamma")
        seen_states: list[ConversationState] = []
        records: list[dict[str, Any]] = []

        class Server(AgentServer):
            def emit_debug(self, *_args: Any, **_kwargs: Any) -> None:
                pass

            async def audio_reader(self, *_args: Any) -> None:
                await asyncio.Future()

            async def next_utterance(self, _queue: Any, session: Any = None) -> UtteranceResult:
                assert session is None
                return dataclasses.replace(metrics().utterance, pcm=clip(2000 + self.slot_index))

            async def get_call_policy(self, _claim: Any) -> dict[str, Any]:
                return {}

            async def commit_completed_orders(self, *_args: Any) -> int:
                return 0

        async def asr(config: Any, pcm: bytes, _debug: Any) -> ASRResult:
            assert pcm == clip(2000 + config.test_index)
            await asyncio.sleep(0.015)
            return ASRResult(words[config.test_index], 1, 1, 0, 1)

        async def llm(config: Any, state: ConversationState, transcript: str, _policy: Any) -> LLMResult:
            assert transcript == words[config.test_index] == state.caller_id
            seen_states.append(state)
            await asyncio.sleep(0.015)
            return LLMResult(transcript, "beenden", [], {})

        def tts(config: Any, text: str, _backend: str, emit: Any, _notify: Any) -> None:
            assert text in ("greeting", words[config.test_index])
            emit(clip(800 if text == "greeting" else 900 + config.test_index))

        async def one(index: int) -> None:
            config = SimpleNamespace(
                test_index=index, slot_count=3, slot_id=lambda i: f"ai-slot-{i:02d}",
                streaming_asr=False, speculative_llm=False, filler_enabled=True,
                filler_start_ms=(60, 90, 600), filler_beep_enabled=True,
                filler_beep_start_ms=0, filler_beep_interval_ms=200,
                filler_beep_frequency_hz=400, filler_beep_duration_ms=20, filler_beep_volume=0.15,
                max_turns=1, greeting="greeting", technical_failure="failure", tts_backend="qwen",
                energy_threshold=520, preroll_ms=300, speech_start_ms=120, speech_end_ms=500,
                performance_enabled=False, performance_log_file=MANAGED_PERFORMANCE_LOG,
                performance_max_bytes=10485760, performance_backup_count=5,
            )
            server, writer = Server(config, index), Writer()
            server.performance.submit = records.append
            try:
                await server.run_call(SimpleNamespace(caller_id=words[index]), None, writer)
                values = [value for _, value in writer.frames]
                assert values.count(900 + index) == 3
                assert all(value in (0, 100, 200, 300, 800, 900 + index) for value in values)
            finally:
                server.performance.close()

        with patch.dict(globals(), load_filler_clips=lambda _config: clips,
                        batch_asr_transcribe=asr, call_llm_async=llm, stream_tts=tts):
            await asyncio.wait_for(asyncio.gather(*(one(index) for index in range(3))), 3)
        assert len({id(state) for state in seen_states}) == 3
        assert {record["slot_id"] for record in records} == {f"ai-slot-{i:02d}" for i in range(3)}
        assert all(record["outcome"] == "completed" for record in records)
        assert all(record["beep_count"] >= 1 for record in records)

    await parallel_calls()
    assert not any(task.get_name() == "static-filler-playback" for task in asyncio.all_tasks()
                   if not task.done())
    print("static filler assets/gaps/three playbacks/reply priority/hangup/metrics self-test: ok")


async def speculative_llm_self_test() -> None:
    from types import SimpleNamespace
    from unittest.mock import patch

    async def eventually(predicate: Callable[[], bool]) -> None:
        async with asyncio.timeout(2):
            while not predicate():
                await asyncio.sleep(0.001)

    # Confirmed segments plus provisional suffix, revisions and invalidation.
    # Neither a partial nor its concatenation may contaminate the final text.
    hypotheses: list[str] = []
    events = iter([
        {"type": "confirmed", "start": 0, "end": 1, "text": "Nummer 42"},
        {"type": "partial", "text": "bitte ändern"},
        {"type": "confirmed", "start": 0, "end": 2, "text": "Nummer 43"},
        {"type": "partial", "text": ""},
        {"type": "partial", "text": None},
        {"type": "end"},
    ])

    class Events:
        async def recv_json(self) -> dict[str, Any]:
            return next(events)

    session = StreamingASRSession(SimpleNamespace(), on_transcript=hypotheses.append)
    session.end_sent = True
    assert await session._receive(Events()) == "Nummer 43"
    assert hypotheses == ["Nummer 42", "Nummer 42 bitte ändern", "Nummer 43", "Nummer 43", ""]

    # HTTP framing, limits, errors and real socket-close path (in-memory streams).
    class Writer:
        def __init__(self) -> None:
            self.closed = False
            self.sent = bytearray()

        def write(self, data: bytes) -> None:
            self.sent.extend(data)

        async def drain(self) -> None:
            pass

        def close(self) -> None:
            self.closed = True

        async def wait_closed(self) -> None:
            pass

    async def http_case(response: bytes | None, expected: str = "") -> None:
        writer = Writer()
        reader = asyncio.StreamReader()
        if response is not None:
            reader.feed_data(response)
            reader.feed_eof()

        async def connect(*_args: Any, **_kwargs: Any) -> tuple[Any, Any]:
            return reader, writer

        config = SimpleNamespace(llm_url="http://synthetic/v1/chat/completions", http_timeout=0.02)
        with patch.object(asyncio, "open_connection", connect):
            task = asyncio.create_task(async_llm_envelope(config, {"synthetic": True}))
            if expected == "cancel":
                await eventually(lambda: bool(writer.sent))
                task.cancel()
                result = await asyncio.gather(task, return_exceptions=True)
                assert isinstance(result[0], asyncio.CancelledError)
            elif expected:
                try:
                    await task
                except ProtocolError as error:
                    assert str(error) == expected, (str(error), expected)
                else:
                    raise AssertionError("invalid LLM response accepted")
            else:
                assert await task == {"ok": True}
        assert writer.closed
        assert b"Connection: close\r\n" in writer.sent

    prefix = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
    body = b'{"ok":true}'
    await http_case(prefix + b"Content-Length: 11\r\n\r\n" + body)
    await http_case(prefix + b"Transfer-Encoding: chunked\r\n\r\nB\r\n" + body + b"\r\n0\r\n\r\n")
    await http_case(prefix + b"\r\n" + body)
    await http_case(prefix + b"Content-Length: 3000000\r\n\r\n", "llm_response_too_large")
    await http_case(prefix + b"Content-Length: 50\r\n\r\n{}", "llm_response_invalid")
    await http_case(prefix + b"Content-Length: 1\r\n\r\nx", "llm_response_invalid")
    await http_case(b"HTTP/1.1 503 Busy\r\n\r\n", "llm_http_failure")
    await http_case(prefix + b"Transfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n", "llm_http_framing_invalid")
    await http_case(None, "llm_timeout")
    await http_case(None, "cancel")

    starts: list[tuple[str, str, int]] = []
    cancellations: list[str] = []
    gates: dict[str, asyncio.Event] = {}
    active: dict[str, int] = {}
    policy = {"route": 1, "evaluated_at": "timestamp-1"}
    policy_reads = 0
    controllers: list[SpeculativeLLMTurn] = []
    attempts: dict[str, int] = {}

    async def get_policy() -> dict[str, Any]:
        nonlocal policy_reads
        policy_reads += 1
        return copy.deepcopy(policy)

    def build(_config: Any, state: ConversationState, text: str, rules: Any) -> dict[str, Any]:
        state.pending_au = "synthetic mutation: " + text
        return {"owner": state.caller_id, "text": text, "route": rules["route"]}

    async def infer(_config: Any, payload: Any) -> dict[str, Any]:
        owner, text = payload["owner"], payload["text"]
        active[owner] = active.get(owner, 0) + 1
        assert active[owner] == 1, "overlapping requests for one conversation"
        assert payload["cache_prompt"] is True
        starts.append((owner, text, payload["route"]))
        attempts[text] = attempts.get(text, 0) + 1
        try:
            if text in gates:
                await gates[text].wait()
            if text == "network fail" and attempts[text] == 1:
                raise ConnectionResetError()
            return {"text": text, "route": payload["route"], "attempt": attempts[text]}
        except asyncio.CancelledError:
            cancellations.append(text)
            if text == "late obsolete":
                # Even a late completion after cancellation must never be released.
                return {"text": text, "route": payload["route"]}
            raise
        finally:
            active[owner] -= 1

    def decode(value: Any, state: ConversationState, text: str, rules: Any) -> LLMResult:
        assert value["text"] == text and value["route"] == rules["route"]
        if text == "invalid draft" and value["attempt"] == 1:
            raise ProtocolError("llm_response_invalid")
        state.au_handled = True
        return LLMResult(text, "none", [], value)

    def controller(owner: str) -> tuple[SpeculativeLLMTurn, ConversationState]:
        state = ConversationState("telephone", caller_id=owner)
        item = SpeculativeLLMTurn(SimpleNamespace(), state, get_policy)
        controllers.append(item)
        return item, state

    def started(owner: str, text: str) -> bool:
        return any(row[:2] == (owner, text) for row in starts)

    with (patch.dict(globals(), build_llm_payload=build, async_llm_envelope=infer,
                     decode_llm_envelope=decode),
          patch.object(SpeculativeLLMTurn, "STABLE_SECONDS", 0.004),
          patch.object(SpeculativeLLMTurn, "MIN_START_INTERVAL_SECONDS", 0.008)):
        try:
            item, state = controller("reuse")
            item.offer("confirmed final")
            await asyncio.sleep(0)
            assert not started("reuse", "confirmed final")
            await eventually(lambda: item.current is not None and item.current.task.done())
            assert state.pending_au == "" and state.messages == [] and not state.au_handled
            item.offer("confirmed final")  # duplicate must not restart
            policy["evaluated_at"] = "timestamp-2"
            result, working = await item.finish("confirmed final", state)
            assert result.reply == "confirmed final" and item.reused == 1 and item.requests == 1
            assert working.au_handled and not state.au_handled
            now = time.monotonic_ns()
            metrics = TurnPerformance(1, UtteranceResult(b"", 1, 1, 500, "silence", now, now))
            item.update_metrics(metrics)
            assert metrics.end_of_detected_speech_to_llm_start_ms <= 0
            assert metrics.llm_speculative_reused == 1
            await item.close()

            item, state = controller("revision")
            gates["late obsolete"] = asyncio.Event()
            item.offer("late obsolete")
            await eventually(lambda: started("revision", "late obsolete"))
            item.offer("Ich brauche keine AU, Nummer 42")
            await eventually(lambda: started("revision", "Ich brauche keine AU, Nummer 42"))
            result, _ = await item.finish("Ich brauche keine AU, Nummer 42", state)
            assert result.reply.endswith("42") and item.discarded == 1 and item.reused == 1
            assert "late obsolete" in cancellations and state.pending_au == ""
            await item.close()

            item, state = controller("final correction")
            item.offer("Nummer 42")
            await eventually(lambda: started("final correction", "Nummer 42"))
            result, _ = await item.finish("Nummer 43", state)
            assert result.reply == "Nummer 43" and item.reused == 0 and item.discarded == 1
            await item.close()

            item, state = controller("inflight")
            gates["still computing"] = asyncio.Event()
            item.offer("still computing")
            await eventually(lambda: started("inflight", "still computing"))
            finish = asyncio.create_task(item.finish("still computing", state))
            await asyncio.sleep(0.01)
            assert not finish.done()
            gates["still computing"].set()
            assert (await finish)[0].reply == "still computing" and item.reused == 1
            await item.close()

            item, state = controller("policy before")
            item.offer("policy changes before")
            await eventually(lambda: started("policy before", "policy changes before"))
            policy["route"] = 2
            result, _ = await item.finish("policy changes before", state)
            assert result.raw["route"] == 2 and item.reused == 0
            await item.close()

            item, state = controller("policy during")
            gates["policy changes during"] = asyncio.Event()
            item.offer("policy changes during")
            await eventually(lambda: started("policy during", "policy changes during"))
            reads = policy_reads
            finish = asyncio.create_task(item.finish("policy changes during", state))
            await eventually(lambda: policy_reads > reads)
            policy["route"] = 3
            gates["policy changes during"].set()
            result, _ = await finish
            assert result.raw["route"] == 3 and item.reused == 0 and item.discarded == 1
            await item.close()

            item, state = controller("unstable policy")
            item.offer("unstable policy")
            await eventually(lambda: started("unstable policy", "unstable policy"))
            changes = 0

            async def unstable_policy() -> dict[str, Any]:
                nonlocal changes
                changes += 1
                return {"route": 100 + changes}

            item.get_policy = unstable_policy
            try:
                await item.finish("unstable policy", state)
            except ProtocolError as error:
                assert str(error) == "llm_policy_changed"
            else:
                raise AssertionError("repeatedly changing policy accepted")
            assert attempts["unstable policy"] == 3 and item.reused == 0
            assert state.pending_au == "" and not state.au_handled and not state.messages
            await item.close()

            for text in ("network fail", "invalid draft"):
                item, state = controller(text)
                item.offer(text)
                await eventually(lambda: item.current is not None and item.current.task.done())
                result, _ = await item.finish(text, state)
                assert result.reply == text and item.reused == 0 and item.failures == 1
                assert attempts[text] == 2
                await item.close()

            item, state = controller("snapshot")
            item.offer("snapshot changes")
            await eventually(lambda: started("snapshot", "snapshot changes"))
            state.messages.append({"role": "user", "content": "synthetic confirmed state"})
            _, working = await item.finish("snapshot changes", state)
            assert item.reused == 0 and working.messages == state.messages
            await item.close()

            item, state = controller("budget")
            for number in range(item.MAX_SPECULATIVE_REQUESTS):
                text = f"revision {number}"
                item.offer(text)
                await eventually(lambda: started("budget", text))
            item.offer("budget final")
            await asyncio.sleep(0.025)
            assert not started("budget", "budget final")
            result, _ = await item.finish("budget final", state)
            assert result.reply == "budget final" and item.requests == 3 and item.discarded == 3
            await item.close()

            parallel = [controller(f"slot-{index}") for index in range(3)]
            for index, (item, _) in enumerate(parallel):
                text = f"parallel {index}"
                gates[text] = asyncio.Event()
                item.offer(text)
            await eventually(lambda: all(started(f"slot-{i}", f"parallel {i}") for i in range(3)))
            assert sum(active.values()) == 3
            for index in range(3):
                gates[f"parallel {index}"].set()
            results = await asyncio.gather(*(item.finish(f"parallel {i}", state)
                                             for i, (item, state) in enumerate(parallel)))
            assert [row[0].reply for row in results] == [f"parallel {i}" for i in range(3)]
            for item, _ in parallel:
                await item.close()

            item, state = controller("hangup")
            gates["hangup pending"] = asyncio.Event()
            item.offer("hangup pending")
            await eventually(lambda: started("hangup", "hangup pending"))
            await item.close()
            assert "hangup pending" in cancellations and not state.messages
            assert not any(active.values())
        finally:
            for item in controllers:
                await item.close()
    await asyncio.sleep(0)
    assert not [task for task in asyncio.all_tasks() if task is not asyncio.current_task()
                and task.get_name() in {"llm-candidate", "llm-speculation-manager"}]
    # Actual run_call lifecycle: inference during speech, no result application
    # before final ASR, early reuse/correction and hangup during either wait.
    async def call_case(mode: str) -> None:
        final_gate = asyncio.Event()
        endpoint_gate = asyncio.Event()
        hangup_gate = asyncio.Event()
        inference_gate = asyncio.Event()
        inference_started = asyncio.Event()
        finalizing = asyncio.Event()
        requests: list[str] = []
        spoken: list[str] = []
        applied: list[str] = []
        records: list[dict[str, Any]] = []
        sessions: list[Any] = []
        config = SimpleNamespace(
            slot_count=3, performance_enabled=False, performance_log_file=MANAGED_PERFORMANCE_LOG,
            performance_max_bytes=10485760, performance_backup_count=5,
            streaming_asr=True, speculative_llm=True, greeting="synthetic greeting",
            technical_failure="synthetic failure", max_turns=1, energy_threshold=520,
            preroll_ms=300, speech_start_ms=120, speech_end_ms=500,
            slot_id=lambda index: f"ai-slot-{index:02d}",
        )

        class ASR:
            def __init__(self, _config: Any, _debug: Any, callback: Any) -> None:
                self.callback = callback
                self.closed = False
                sessions.append(self)

            async def finish(self) -> ASRResult:
                finalizing.set()
                await final_gate.wait()
                if mode == "asr failure":
                    raise ProtocolError("asr_timeout")
                return ASRResult("final corrected" if mode == "correct" else "stable final", 1, 1, 1, 1)

            async def close(self) -> None:
                self.closed = True

        class Server(AgentServer):
            def emit_debug(self, *_args: Any) -> None:
                pass

            async def audio_reader(self, _reader: Any, incoming: Any, *_args: Any) -> None:
                await hangup_gate.wait()
                incoming.put_nowait(None)

            async def next_utterance(self, _queue: Any, session: Any) -> UtteranceResult:
                session.callback("stable final")
                await endpoint_gate.wait()
                now = time.monotonic_ns()
                return UtteranceResult(b"synthetic pcm", 1000, 1800, 500, "silence", now, now - 500_000_000)

            async def get_call_policy(self, _claim: Any) -> dict[str, Any]:
                return {"route": 1}

            async def speak(self, text: str, *_args: Any, **_kwargs: Any) -> TTSMetrics:
                if mode == "asr failure" and text == config.technical_failure:
                    assert inference_stopped.is_set(), "inference still active during error TTS"
                spoken.append(text)
                return TTSMetrics("qwen", 1, 1, time.monotonic_ns(), 1, 1)

            async def commit_completed_orders(self, _claim: Any, state: ConversationState) -> int:
                assert bool(state.messages) == bool(applied)
                return 0

        inference_stopped = asyncio.Event()

        async def network(_config: Any, payload: Any) -> dict[str, Any]:
            assert payload["id_slot"] == 2
            requests.append(payload["text"])
            inference_started.set()
            try:
                await inference_gate.wait()
                return {"text": payload["text"], "route": 1, "attempt": 1}
            finally:
                inference_stopped.set()

        def decode_call(value: Any, state: Any, text: str, rules: Any) -> LLMResult:
            assert final_gate.is_set() and not hangup_gate.is_set()
            assert value["text"] == text
            return LLMResult(text, "beenden", [], {})

        def apply(state: Any, result: Any, text: str) -> None:
            assert final_gate.is_set() and not hangup_gate.is_set()
            applied.append(text)
            state.messages.append({"role": "user", "content": text})

        server = Server(config, 2)
        server.performance.submit = records.append
        with (patch.dict(globals(), StreamingASRSession=ASR, build_llm_payload=build,
                         async_llm_envelope=network, decode_llm_envelope=decode_call,
                         apply_llm_result=apply),
              patch.object(SpeculativeLLMTurn, "STABLE_SECONDS", 0.001)):
            task = asyncio.create_task(server.run_call(SimpleNamespace(caller_id="synthetic"), None, Writer()))
            try:
                await asyncio.wait_for(inference_started.wait(), 1)
                assert not endpoint_gate.is_set() and not applied
                assert spoken == ["synthetic greeting"]
                endpoint_gate.set()
                await asyncio.wait_for(finalizing.wait(), 1)
                if mode == "hangup asr":
                    hangup_gate.set()
                elif mode == "asr failure":
                    final_gate.set()
                elif mode == "hangup llm":
                    final_gate.set()
                    await asyncio.sleep(0.01)
                    hangup_gate.set()
                else:
                    inference_gate.set()
                    await asyncio.sleep(0.002)
                    assert not applied and len(spoken) == 1
                    final_gate.set()
                await asyncio.wait_for(task, 1)
            finally:
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
                server.performance.close()
        assert len(records) == 1 and all(session.closed for session in sessions)
        record = records[0]
        assert set(record) == PERFORMANCE_RECORD_KEYS
        assert record["pipeline_mode"] == "streaming_asr_speculative_llm"
        if mode.startswith("hangup"):
            assert not applied and len(spoken) == 1
            assert record["outcome"] == "caller_hangup"
        elif mode == "asr failure":
            assert not applied and spoken == [config.greeting, config.technical_failure]
            assert record["outcome"] == "failed" and record["error_code"] == "asr_timeout"
        else:
            final = "final corrected" if mode == "correct" else "stable final"
            assert applied == [final] and spoken == ["synthetic greeting", final]
            assert record["outcome"] == "completed"
            assert record["llm_speculative_requests"] == 1
            assert record["llm_speculative_reused"] == int(mode == "reuse")
            assert record["llm_wait_after_asr_final_ms"] is not None
            if mode == "reuse":
                assert len(requests) == 1 and record["end_of_detected_speech_to_llm_start_ms"] <= 0
            else:
                assert requests == ["stable final", "final corrected"]

    for mode in ("reuse", "correct", "hangup asr", "hangup llm", "asr failure"):
        await call_case(mode)
    await asyncio.sleep(0)
    assert not [task for task in asyncio.all_tasks() if task is not asyncio.current_task()
                and task.get_name() in {"llm-candidate", "llm-speculation-manager"}]
    print("speculative LLM isolation/revisions/policy/cancellation/HTTP/call-path self-test: ok")


async def streaming_asr_self_test() -> None:
    """Exercise the wire protocol in memory, without services, GPUs or ports."""
    from types import SimpleNamespace
    from unittest.mock import patch

    gateways: list[Any] = []
    final_gate = asyncio.Event()
    final_gate.set()
    connect_gate = asyncio.Event()
    connect_gate.set()
    callbacks: list[asyncio.Task[Any]] = []

    class Gateway:
        def __init__(self) -> None:
            self.reader = asyncio.StreamReader()
            self.pcm = bytearray()
            self.first_audio = asyncio.Event()
            self.ended = asyncio.Event()
            self.closed = False
            self.mode = "normal"
            self.pongs = 0
            self.frames = 0

        def event(self, event: Mapping[str, Any], fragmented: bool = False) -> None:
            data = json.dumps(event).encode()
            if fragmented:
                middle = len(data) // 2
                self.reader.feed_data(bytes([0x01, middle]) + data[:middle])
                self.reader.feed_data(bytes([0x80, len(data) - middle]) + data[middle:])
            else:
                header = bytes([0x81, len(data)]) if len(data) < 126 else (
                    b"\x81\x7e" + struct.pack("!H", len(data))
                )
                self.reader.feed_data(header + data)

        async def finalize(self) -> None:
            await final_gate.wait()
            if self.closed:
                return
            if self.mode == "timeout":
                return
            if self.mode not in {"empty", "partial_only"}:
                self.event({"type": "confirmed", "start": 0, "end": 2,
                            "text": "synthetic corrected final"})
            self.event({"type": "end"})
            self.ended.set()

        def write(self, packet: bytes) -> None:
            if packet.startswith(b"GET "):
                self.mode = packet.split(b" ", 2)[1].decode().lstrip("/")
                key = packet.split(b"Sec-WebSocket-Key: ", 1)[1].split(b"\r\n", 1)[0]
                accept = base64.b64encode(hashlib.sha1(
                    key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
                ).digest())
                self.reader.feed_data(
                    b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                    b"Connection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n"
                )
                self.event({"type": "ready", "protocol": "kienzlefon-asr-v1",
                            "audio": {"encoding": "pcm_s16le",
                                      "sample_rate": 8000 if self.mode == "bad_ready" else 16000,
                                      "channels": 1}})
                return
            assert packet[1] & 0x80  # Clients must mask every frame, including EOF/pong.
            opcode = packet[0] & 0x0f
            length, offset = packet[1] & 0x7f, 2
            if length == 126:
                length, offset = struct.unpack("!H", packet[2:4])[0], 4
            elif length == 127:
                length, offset = struct.unpack("!Q", packet[2:10])[0], 10
            mask = packet[offset:offset + 4]
            data = bytes(value ^ mask[index & 3]
                         for index, value in enumerate(packet[offset + 4:]))
            assert len(data) == length
            if opcode == 10:
                assert data == b"ping"
                self.pongs += 1
                return
            assert opcode == 2
            if not data:
                callbacks.append(asyncio.create_task(self.finalize()))
                return
            assert not self.ended.is_set()
            self.pcm.extend(data)
            self.frames += 1
            if not self.first_audio.is_set():
                self.first_audio.set()
                self.reader.feed_data(b"\x89\x04ping")
                self.event({"type": "partial", "text": "synthetic unstable"}, fragmented=True)
                if self.mode == "close":
                    self.reader.feed_data(b"\x88\x00")
                elif self.mode == "error":
                    self.event({"type": "error", "message": "untrusted details"})
                elif self.mode == "premature":
                    self.event({"type": "end"})
                elif self.mode not in {"empty", "partial_only"}:
                    self.event({"type": "confirmed", "start": 0, "end": 1,
                                "text": "synthetic draft"})

        async def drain(self) -> None:
            await asyncio.sleep(0)

        def close(self) -> None:
            self.closed = True
            self.reader.feed_eof()

        async def wait_closed(self) -> None:
            return None

    async def connect(*_args: Any, **_kwargs: Any) -> tuple[Any, Any]:
        await connect_gate.wait()
        gateway = Gateway()
        gateways.append(gateway)
        return gateway.reader, gateway

    def configuration(mode: str = "normal") -> Any:
        return SimpleNamespace(
            asr_url=f"ws://synthetic/{mode}", asr_timeout=0.25,
            maximum_utterance_ms=30000, minimum_utterance_ms=240,
            energy_threshold=520, preroll_ms=300, speech_start_ms=120,
            speech_end_ms=500, debug_metrics_interval_ms=250,
            slot_count=3, performance_enabled=False,
            performance_log_file=MANAGED_PERFORMANCE_LOG,
            performance_max_bytes=10485760, performance_backup_count=5,
            debug_allow_sensitive_console=False, streaming_asr=True,
            slot_id=lambda index: f"ai-slot-{index:02d}",
        )

    silence = b"\0" * TELEPHONY_FRAME_BYTES
    speech = struct.pack("<h", 2000) * (TELEPHONY_FRAME_BYTES // 2)

    async def normal_turn(index: int) -> None:
        prior_gateway_count = len(gateways)
        config = configuration()
        server = AgentServer(config, index)
        hypotheses: list[str] = []
        session = StreamingASRSession(config, on_transcript=hypotheses.append)
        audio: asyncio.Queue[Any] = asyncio.Queue()
        speech_frame = struct.pack("<h", 2000 + index) * (TELEPHONY_FRAME_BYTES // 2)
        prefix = [silence] * 15 + [speech_frame] * 20
        suffix = [silence] * 10 + [speech_frame] * 12 + [silence] * 25
        utterance_task = asyncio.create_task(server.next_utterance(audio, session))
        try:
            for frame in prefix:
                await audio.put(frame)
                await asyncio.sleep(0)
            while not any(g.pcm and speech_frame in g.pcm for g in gateways[prior_gateway_count:]):
                await asyncio.sleep(0)
            gateway = next(g for g in gateways[prior_gateway_count:] if speech_frame in g.pcm)
            assert not utterance_task.done() and not gateway.ended.is_set()
            assert session.task is not None and not session.task.done()
            for frame in suffix:
                await audio.put(frame)
                await asyncio.sleep(0)
            utterance = await utterance_task
            assert utterance and utterance.pcm == b"".join((prefix + suffix)[6:])
            result_task = asyncio.create_task(session.finish())
            await asyncio.sleep(0)
            result = await result_task
            assert gateway.ended.is_set()
            assert bytes(gateway.pcm) == utterance.pcm  # No missing/double preroll or endpoint frame.
            assert result.transcript == "synthetic corrected final"
            assert result.confirmed_count == 2 and result.partial_count == 1
            assert hypotheses == ["synthetic unstable", "synthetic draft", "synthetic corrected final"]
            assert gateway.pongs == 1
        finally:
            utterance_task.cancel()
            await asyncio.gather(utterance_task, return_exceptions=True)
            await session.close()
            server.performance.close()

    async def rejected(mode: str, expected: str) -> None:
        session = StreamingASRSession(configuration(mode))
        session.start(speech)
        try:
            # Give early server errors/end a chance before client EOF.
            for _ in range(20):
                await asyncio.sleep(0)
            try:
                await session.finish()
            except ProtocolError as error:
                assert str(error) == expected, (mode, str(error))
            else:
                raise AssertionError(f"accepted invalid ASR result: {mode}")
        finally:
            await session.close()

    async def call_path(streaming: bool, disconnect: bool = False) -> None:
        # Exercise the actual run_call branch, with synthetic media/services.
        config = configuration()
        config.streaming_asr = streaming
        config.max_turns = 1
        config.greeting = "synthetic greeting"
        config.technical_failure = "synthetic failure"
        config.tts_backend = "qwen"
        events: list[str] = []
        records: list[dict[str, Any]] = []
        batch_inputs: list[bytes] = []
        disconnect_gate = asyncio.Event()

        class CallServer(AgentServer):
            def emit_debug(self, event: str, *_args: Any) -> None:
                events.append(event)

            async def audio_reader(self, _reader: Any, incoming: Any,
                                   listening: Any, _stats: Any) -> None:
                await listening.wait()
                for frame in [silence] * 15 + [speech] * 20 + [silence] * 25:
                    await incoming.put(frame)
                    await asyncio.sleep(0)
                if disconnect:
                    await disconnect_gate.wait()
                    await incoming.put(None)
                else:
                    await asyncio.Future()

            async def speak(self, _text: str, *_args: Any, **_kwargs: Any) -> TTSMetrics:
                return TTSMetrics("qwen", 0, 0, time.monotonic_ns(), 0, 0)

            async def get_call_policy(self, _claim: Any) -> dict[str, Any]:
                return {}

            async def commit_completed_orders(self, *_args: Any) -> int:
                return 0

        class Writer:
            def write(self, _data: bytes) -> None:
                pass

            async def drain(self) -> None:
                pass

        count = len(gateways)
        async def llm(_config: Any, _state: Any, transcript: str, _policy: Any) -> LLMResult:
            assert transcript == "synthetic corrected final"
            assert "speech_end" in events
            if streaming:
                assert len(gateways) == count + 1 and gateways[-1].ended.is_set()
            else:
                assert len(gateways) == count and batch_inputs
            events.append("llm_called")
            return LLMResult("synthetic reply", "beenden", [], {})

        async def batch(_config: Any, pcm: bytes, _debug: Any) -> ASRResult:
            assert "speech_end" in events
            batch_inputs.append(pcm)
            return ASRResult("synthetic corrected final", 1, 1, 0, 1)

        server = CallServer(config, 0)
        server.performance.submit = records.append
        final_gate.clear()
        with patch.dict(globals(), call_llm_async=llm, batch_asr_transcribe=batch):
            task = asyncio.create_task(server.run_call(
                SimpleNamespace(caller_id=""), None, Writer()
            ))
            try:
                if streaming:
                    while len(gateways) == count or not gateways[-1].first_audio.is_set():
                        await asyncio.sleep(0)
                    for _ in range(100):
                        await asyncio.sleep(0)
                    assert "llm_called" not in events and not task.done()
                if disconnect:
                    disconnect_gate.set()
                else:
                    final_gate.set()
                await task
            finally:
                final_gate.set()
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
                server.performance.close()
        if disconnect:
            assert "llm_called" not in events
            assert len(records) == 1 and records[0]["outcome"] == "caller_hangup"
            assert gateways[-1].closed
            return
        assert events.count("llm_called") == 1
        assert len(records) == 1 and records[0]["outcome"] == "completed"
        record = records[0]
        assert set(record) == PERFORMANCE_RECORD_KEYS
        assert record["pipeline_mode"] == ("streaming_asr" if streaming else "half_duplex")
        assert record["asr_final_after_speech_end_ms"] >= 0
        assert record["end_of_detected_speech_to_llm_start_ms"] >= record["asr_final_after_speech_end_ms"]

    with patch("asyncio.open_connection", side_effect=connect):
        async with asyncio.timeout(10):
            # 2.5.1 whole-utterance upload exceeds the bounded send queue and
            # must backpressure, never drop audio or fail with queue overflow.
            block_config = configuration()
            block_config.asr_timeout = 2
            blocks = [speech * 300, speech * 175, speech * 125]
            results = await asyncio.gather(*(batch_asr_transcribe(block_config, pcm)
                                             for pcm in blocks))
            assert all(result.transcript == "synthetic corrected final" for result in results)
            assert sorted(len(g.pcm) for g in gateways) == sorted(map(len, blocks))
            assert all(bytes(g.pcm) == speech * g.frames and g.ended.is_set() and g.closed
                       for g in gateways)
            # Cancellation while the producer is blocked on a full queue.
            connect_gate.clear()
            upload = asyncio.create_task(batch_asr_transcribe(block_config, speech * 300))
            for _ in range(20):
                await asyncio.sleep(0)
            upload.cancel()
            await asyncio.gather(upload, return_exceptions=True)
            assert not any(t.get_name() == "asr-block-upload" for t in asyncio.all_tasks()
                           if not t.done())
            connect_gate.set()
            try:
                await batch_asr_transcribe(configuration("timeout"), speech * 150)
            except ProtocolError as error:
                assert str(error) == "asr_finalization_timeout"
            else:
                raise AssertionError("block ASR timeout ignored")
            await asyncio.gather(*(normal_turn(index) for index in range(3)))
            await rejected("bad_ready", "asr_ready_contract_mismatch")
            await rejected("close", "websocket_closed_before_end")
            await rejected("error", "asr_reported_error")
            await rejected("premature", "asr_end_before_endpoint")
            await rejected("partial_only", "asr_empty_confirmed_transcript")
            await rejected("timeout", "asr_finalization_timeout")

            # A provisional confirmed segment must not release a turn.
            final_gate.clear()
            session = StreamingASRSession(configuration())
            session.start(speech)
            finish = asyncio.create_task(session.finish())
            for _ in range(30):
                await asyncio.sleep(0)
            assert session.confirmed_count == 1 and not finish.done()
            final_gate.set()
            assert (await finish).transcript == "synthetic corrected final"
            await session.close()

            # Saturated connection: fail closed, no unbounded buffer or silent drop.
            connect_gate.clear()
            session = StreamingASRSession(configuration())
            session.start(speech)
            for _ in range(session.MAX_PENDING_FRAMES):
                session.feed(speech)
            assert session.pending.qsize() == session.MAX_PENDING_FRAMES
            try:
                await session.finish()
            except ProtocolError as error:
                assert str(error) == "asr_audio_queue_overrun"
            else:
                raise AssertionError("ASR backpressure was ignored")
            await session.close()
            connect_gate.set()

            # Hangup and rejected short speech both discard the pending ASR session.
            for hangup in (True, False):
                config = configuration()
                server = AgentServer(config, 0)
                session = StreamingASRSession(config)
                audio = asyncio.Queue()
                for frame in [silence] * 15 + [speech] * 6:
                    audio.put_nowait(frame)
                if hangup:
                    audio.put_nowait(None)
                else:
                    for _ in range(25):
                        audio.put_nowait(silence)
                result = await server.next_utterance(audio, session)
                assert result is None if hangup else result is not None and not result.pcm
                await session.close()
                assert session.task is not None and session.task.done()
                server.performance.close()

            # Legacy collection opens no ASR connection while the caller speaks.
            count = len(gateways)
            server = AgentServer(configuration(), 0)
            audio = asyncio.Queue()
            for frame in [speech] * 20 + [silence] * 25:
                audio.put_nowait(frame)
            assert (await server.next_utterance(audio)).pcm
            assert len(gateways) == count
            server.performance.close()
            await call_path(True)
            await call_path(False)
            await call_path(True, disconnect=True)
    await asyncio.gather(*callbacks)
    assert all(g.closed for g in gateways)
    assert not any(t.get_name().startswith("asr-") for t in asyncio.all_tasks()
                   if t is not asyncio.current_task())
    print("streaming ASR protocol/concurrency/cancellation self-test: ok")


def self_test() -> int:
    asyncio.run(filler_self_test())
    asyncio.run(configurable_filler_self_test())
    asyncio.run(speculative_llm_self_test())
    asyncio.run(streaming_asr_self_test())

    def broken_debug_callback(
        _event: str,
        _values: Mapping[str, Any],
        _sensitive: Mapping[str, Any] | None,
    ) -> None:
        raise RuntimeError("synthetic_debug_failure")

    debug_notify(broken_debug_callback, "test", {"value": 1})

    utterance_metrics = UtteranceResult(
        pcm=b"\0" * TELEPHONY_FRAME_BYTES,
        speech_duration_ms=800,
        utterance_ms=1420,
        endpoint_silence_ms=500,
        endpoint_reason="silence",
        endpoint_detected_monotonic_ns=2_000_000_000,
        actual_speech_end_monotonic_ns=1_500_000_000,
    )
    turn_metrics = TurnPerformance(turn=1, utterance=utterance_metrics)
    apply_tts_performance(
        turn_metrics,
        TTSMetrics(
            backend="qwen",
            first_audio_generated_ms=90,
            first_audio_written_ms=95,
            first_audio_written_monotonic_ns=3_250_000_000,
            duration_ms=900,
            audio_ms=860,
        ),
        reply_chars=42,
    )
    assert turn_metrics.end_of_detected_speech_to_first_reply_audio_ms == 1250
    assert turn_metrics.end_of_actual_speech_to_first_reply_audio_ms == 1750
    assert turn_metrics.tts_first_audio_written_ms == 95

    def synthetic_performance_record(sequence: int) -> dict[str, Any]:
        record = {key: None for key in PERFORMANCE_RECORD_KEYS}
        record.update({
            "schema": PERFORMANCE_SCHEMA,
            "schema_version": 1,
            "program_version": VERSION,
            "recorded_at": "2026-09-27T12:00:00.000+00:00",
            "epoch_ms": 1_800_000_000_000 + sequence,
            "slot_id": f"ai-slot-{sequence % 3:02d}",
            "call_sequence": sequence,
            "turn": 1,
            "channel": "telephone",
            "pipeline_mode": "half_duplex",
            "outcome": "completed",
            "endpoint_reason": "silence",
            "end_of_actual_speech_to_first_reply_audio_ms": 2000 + sequence,
            "audio_queue_dropped_frames": 0,
        })
        return record

    with tempfile.TemporaryDirectory(prefix="kzf-performance-") as directory:
        log_path = Path(directory) / "performance.jsonl"
        disabled_path = Path(directory) / "disabled.jsonl"
        disabled = PerformanceWriter(False, disabled_path, 1048576, 2)
        disabled.submit(synthetic_performance_record(0))
        disabled.close()
        assert not disabled_path.exists()

        writers = [PerformanceWriter(True, log_path, 1048576, 2) for _ in range(3)]

        def submit_rows(writer_index: int) -> None:
            for offset in range(20):
                writers[writer_index].submit(
                    synthetic_performance_record(writer_index * 20 + offset)
                )

        threads = [
            threading.Thread(target=submit_rows, args=(index,))
            for index in range(3)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        for writer in writers:
            writer.close()
        lines = log_path.read_text(encoding="ascii").splitlines()
        assert len(lines) == 60
        decoded = [json.loads(line) for line in lines]
        assert all(row["program_version"] == "2.5.1" for row in decoded)
        assert all(set(row) == PERFORMANCE_RECORD_KEYS for row in decoded)
        assert "Müller" not in log_path.read_text(encoding="ascii")
        assert stat.S_IMODE(log_path.stat().st_mode) == 0o640

        rotating_path = Path(directory) / "rotating.jsonl"
        rotating = PerformanceWriter(True, rotating_path, 1024, 2)
        for sequence in range(40):
            rotating.submit(synthetic_performance_record(sequence))
        rotating.close()
        rotated_paths = [
            path for path in (
                rotating_path,
                Path(f"{rotating_path}.1"),
                Path(f"{rotating_path}.2"),
            ) if path.exists()
        ]
        assert len(rotated_paths) == 3
        for path in rotated_paths:
            for line in path.read_text(encoding="ascii").splitlines():
                assert json.loads(line)["schema"] == PERFORMANCE_SCHEMA

    assembler = ConfirmedTranscriptAssembler()
    assembler.add("Europa und", 0.0, 1.0)
    assembler.add("Europa und Asien", 0.0, 1.4)
    assembler.add("sind genannt", 1.5, 2.2)
    assert assembler.transcript() == "Europa und Asien sind genannt"

    source = array.array("h", [0, 1000, -1000, 2000, -2000] * 160)
    if sys.byteorder != "little":
        source.byteswap()
    converted = pcm_resample(source.tobytes(), 8000, 16000)
    assert len(converted) >= len(source.tobytes()) * 2 - 4
    streaming = BandlimitedPCMResampler(8000, 16000)
    raw_source = source.tobytes()
    chunked = b"".join(
        streaming.feed(raw_source[offset : offset + 137])
        for offset in range(0, len(raw_source), 137)
    ) + streaming.feed(b"", final=True)
    assert chunked == converted

    for native_rate in (24000, 22050):
        native = array.array(
            "h",
            (
                round(12000 * math.sin(2.0 * math.pi * 1000 * index / native_rate))
                for index in range(native_rate // 10)
            ),
        )
        if sys.byteorder != "little":
            native.byteswap()
        native_bytes = native.tobytes()
        offline = pcm_resample(native_bytes, native_rate, TELEPHONY_RATE)
        expected_samples = (
            len(native) * TELEPHONY_RATE + native_rate - 1
        ) // native_rate
        assert len(offline) == expected_samples * PCM_WIDTH
        streaming_native = BandlimitedPCMResampler(native_rate, TELEPHONY_RATE)
        streamed = b"".join(
            streaming_native.feed(native_bytes[offset : offset + 137])
            for offset in range(0, len(native_bytes), 137)
        ) + streaming_native.feed(b"", final=True)
        assert streamed == offline

    def tone_rms(frequency: int) -> float:
        native = array.array(
            "h",
            (
                round(12000 * math.sin(2.0 * math.pi * frequency * index / 24000))
                for index in range(4800)
            ),
        )
        if sys.byteorder != "little":
            native.byteswap()
        converted_tone = array.array("h")
        converted_tone.frombytes(pcm_resample(native.tobytes(), 24000, 16000))
        if sys.byteorder != "little":
            converted_tone.byteswap()
        interior = converted_tone[200:-200]
        return math.sqrt(
            sum(int(value) * int(value) for value in interior) / len(interior)
        )

    passband_rms = tone_rms(1000)
    stopband_rms = tone_rms(10000)
    assert passband_rms > 7000
    assert stopband_rms < passband_rms * 0.03

    class VADConfig:
        energy_threshold = 520
        speech_start_ms = 120
        speech_end_ms = 800
        minimum_utterance_ms = 240
        maximum_utterance_ms = 30000
        preroll_ms = 300

    frame_samples = TELEPHONY_FRAME_BYTES // PCM_WIDTH
    silence = b"\0\0" * frame_samples
    speech_samples = array.array("h", [2000] * frame_samples)
    if sys.byteorder != "little":
        speech_samples.byteswap()
    speech = speech_samples.tobytes()

    def vad_result(speech_count: int) -> bytes | None:
        vad = EnergyVAD(VADConfig())  # type: ignore[arg-type]
        result: bytes | None = None
        for frame in [silence] * 15 + [speech] * speech_count + [silence] * 40:
            candidate = vad.feed(frame)
            if candidate is not None:
                result = candidate
        return result

    assert vad_result(6) == b""
    assert vad_result(12)
    reason_vad = EnergyVAD(VADConfig())  # type: ignore[arg-type]
    reason_result: bytes | None = None
    for reason_frame in [silence] * 15 + [speech] * 12 + [silence] * 40:
        candidate = reason_vad.feed(reason_frame)
        if candidate is not None:
            reason_result = candidate
    assert reason_result and reason_vad.last_end_reason == "silence"
    assert reason_vad.last_accepted is True
    assert reason_vad.last_silence_frames == 40

    message_state = ConversationState(channel="telephone", caller_id="+4912345")
    message_state.orders.append(
        OrderState(
            "order-001",
            "termin",
            {**{name: "" for name in ALL_FIELDS}, "grund": "Kontrolle"},
            "",
            False,
        )
    )
    message_state.next_order_number = 2
    message_state.messages.extend(
        [
            {"role": "user", "content": "Erste Angabe"},
            {"role": "assistant", "content": "Erste Rückfrage"},
        ]
    )
    class PromptConfig:
        system_prompt = "Konfigurierter Prompt mit genau diesen vier Schlüsseln: " + ", ".join(ALL_FIELDS)
        telephone_overlay = "Telefonkanal"
        chat_overlay = "Chatkanal"

    llm_messages = build_llm_messages(  # type: ignore[arg-type]
        PromptConfig(), message_state, "Zweite Angabe", synthetic_call_policy(True)
    )
    assert llm_messages[0]["role"] == "system"
    assert sum(message["role"] == "system" for message in llm_messages) == 1
    assert all(message["role"] != "system" for message in llm_messages[1:])
    assert "Aktueller bestätigter Arbeitszustand:" in llm_messages[0]["content"]
    assert '"call_type":"termin"' in llm_messages[0]["content"]
    assert "Telefonkanal" in llm_messages[0]["content"]
    assert "genau diesen vier Schlüsseln" in llm_messages[0]["content"]
    assert all(name in llm_messages[0]["content"] for name in ALL_FIELDS)
    assert llm_messages[-1] == {"role": "user", "content": "Zweite Angabe"}

    schema = llm_schema()
    serialized_schema = json.dumps(schema, separators=(",", ":"))
    assert "minLength" not in serialized_schema
    assert "maxLength" not in serialized_schema
    assert schema["required"] == ["reply", "caller_role", "urgency", "action", "orders"]
    assert schema["additionalProperties"] is False
    order_schema = schema["properties"]["orders"]["items"]
    assert order_schema["required"] == [
        "complete", "call_type", "fields", "zusammenfassung"
    ]
    assert order_schema["properties"]["call_type"] == {
        "enum": list(ALLOWED_CALL_TYPES)
    }
    assert order_schema["properties"]["fields"]["required"] == list(ALL_FIELDS)
    assert order_schema["properties"]["fields"]["additionalProperties"] is False
    assert diagnostic_error_code(ProtocolError("llm_json_shape_invalid")) == (
        "llm_json_shape_invalid"
    )
    assert diagnostic_error_code(ProtocolError("unsafe detail with spaces")) == (
        "ProtocolError"
    )
    assert diagnostic_error_code(RuntimeError("private detail")) == "RuntimeError"

    fields = {name: "" for name in ALL_FIELDS}
    fields.update(
        {
            "vorname": "Max",
            "nachname": "Muster",
            "geburtsdatum": "01.01.1970",
            "grund": "Kontrolle",
        }
    )
    result = validate_llm_result(
        {
            "reply": "Danke.",
            "action": "none",
            "orders": [{
                "complete": True,
                "call_type": "termin",
                "fields": fields,
                "zusammenfassung": "Terminwunsch zur Kontrolle.",
            }],
        },
        ConversationState(channel="telephone"),
        synthetic_call_policy(True),
    )
    assert result.orders[0].complete and result.orders[0].call_type == "termin"
    try:
        validate_llm_result(
            {"action": "none", "orders": []},
            ConversationState(channel="telephone"),
            synthetic_call_policy(True),
        )
    except ProtocolError as error:
        assert str(error) == "llm_json_shape_invalid"
    else:
        raise AssertionError("LLM result without reply accepted")
    incomplete_fields = dict(fields)
    incomplete_fields["grund"] = ""
    repaired = validate_llm_result(
        {
            "reply": "Wie lautet der Grund?",
            "action": "none",
            "orders": [{
                "complete": True,
                "call_type": "termin",
                "fields": incomplete_fields,
                "zusammenfassung": "",
            }],
        },
        ConversationState(channel="telephone"),
        synthetic_call_policy(True),
    )
    assert repaired.orders[0].complete is False
    assert "order_0_complete_downgraded" in repaired.repairs

    preserved_state = ConversationState(channel="telephone")
    apply_llm_result(preserved_state, result, "Erste Angabe")
    preserved = validate_llm_result(
        {"reply": "Noch etwas?", "action": "warteschlange", "orders": []},
        preserved_state,
        synthetic_call_policy(True),
    )
    assert len(preserved.orders) == 1 and preserved.orders[0].complete
    assert preserved.action == "none"
    assert "transfer_with_order_rejected" in preserved.repairs

    second_fields = {name: "" for name in ALL_FIELDS}
    second_fields["grund"] = "Zweiter Terminwunsch"
    same_type_added = validate_llm_result(
        {
            "reply": "Wie lautet Ihr Geburtsdatum?",
            "action": "none",
            "orders": [{
                "complete": False,
                "call_type": "termin",
                "fields": second_fields,
                "zusammenfassung": "Zweiter Terminwunsch.",
            }],
        },
        preserved_state,
        synthetic_call_policy(True),
    )
    assert len(same_type_added.orders) == 2
    assert same_type_added.orders[0].complete is True
    assert same_type_added.orders[1].order_id != same_type_added.orders[0].order_id

    chat_transfer = validate_llm_result(
        {"reply": "Ich verbinde.", "action": "rotes_telefon", "orders": []},
        ConversationState(channel="chat"),
        synthetic_call_policy(True),
    )
    assert chat_transfer.action == "none"
    assert "chat_transfer_rejected" in chat_transfer.repairs
    assert validate_call_policy(synthetic_call_policy(False))["phone_open"] is False

    class TextTestConfig:
        greeting = "Bereits abgespielt"
        debug_allow_sensitive_console = True

    text_runtime = TextRuntime(TextTestConfig())  # type: ignore[arg-type]
    telephone_session_id = text_runtime.create_session({
        "channel": "telephone",
        "caller_id": "+4912345",
        "environment": {"within_phone_hours": True},
    })["session_id"]
    chat_session_id = text_runtime.create_session({"channel": "chat"})["session_id"]
    order_session_id = text_runtime.create_session({"channel": "telephone"})["session_id"]
    persistent_session_id = text_runtime.create_session({
        "channel": "chat",
        "recording_mode": "spool",
    })["session_id"]
    try:
        text_runtime.create_session({
            "channel": "telephone",
            "recording_mode": "spool",
        })
    except ProtocolError as error:
        assert str(error) == "text_spool_channel_invalid"
    else:
        raise AssertionError("persistent telephone text session accepted")
    original_call_llm = globals()["call_llm"]
    original_commit_order = globals()["commit_order"]
    committed_orders: list[tuple[str, str, str]] = []

    def fake_call_llm(
        _config: AgentConfig,
        state: ConversationState,
        transcript: str,
        policy: Mapping[str, Any],
    ) -> LLMResult:
        if transcript in {
            "Auftrag",
            "Überweisung für Müller, Größe, Straße, äöüÄÖÜß",
        }:
            order_fields = {name: "" for name in ALL_FIELDS}
            order_fields["anliegen"] = (
                "Überweisung für Müller, Größe, Straße, äöüÄÖÜß"
                if transcript != "Auftrag"
                else "Synthetische Nachricht"
            )
            raw = {
                "reply": (
                    "Danke, Müller. Größe, Straße, äöüÄÖÜß."
                    if transcript != "Auftrag"
                    else "Danke und auf Wiedersehen."
                ),
                "caller_role": "patient",
                "urgency": "normal",
                "action": "beenden",
                "orders": [{
                    "complete": True,
                    "call_type": "sonstiges",
                    "fields": order_fields,
                    "zusammenfassung": order_fields["anliegen"] + ".",
                }],
            }
        else:
            raw = {
                "reply": "Ich stelle weiter.",
                "caller_role": "professional_urgent",
                "urgency": "normal",
                "action": "rotes_telefon",
                "orders": [],
            }
        return validate_llm_result(raw, state, policy)

    def fake_commit_order(
        _config: AgentConfig,
        request_id: str,
        caller_id: str,
        order: OrderState,
    ) -> str:
        committed_orders.append(
            (request_id, caller_id, order.fields.get("anliegen", ""))
        )
        return "call-synthetic-1"

    globals()["call_llm"] = fake_call_llm
    globals()["commit_order"] = fake_commit_order
    try:
        telephone_result = text_runtime.turn(
            telephone_session_id, {"text": "Fachdienst"}
        )
        assert telephone_result["terminal"] is True
        assert telephone_result["action_result"] == {
            "action": "rotes_telefon",
            "handoff_target": "super_priority",
            "requested": True,
            "executed": False,
            "reason": "text_transport_no_handoff",
        }
        chat_result = text_runtime.turn(chat_session_id, {"text": "Fachdienst"})
        assert chat_result["terminal"] is False
        assert chat_result["normalized_response"]["action"] == "none"
        assert "chat_transfer_rejected" in chat_result["repairs"]
        order_result = text_runtime.turn(order_session_id, {"text": "Auftrag"})
        assert order_result["terminal"] is True
        assert len(order_result["records"]) == 1
        assert order_result["records"][0]["adapter"] == "text_recording"
        assert text_runtime.hangup(order_session_id)["records"] == order_result["records"]
        utf8_text = "Überweisung für Müller, Größe, Straße, äöüÄÖÜß"
        persistent_result = text_runtime.turn(
            persistent_session_id, {"text": utf8_text}
        )
        assert persistent_result["terminal"] is True
        assert persistent_result["recording_mode"] == "spool"
        assert persistent_result["reply"] == "Danke, Müller. Größe, Straße, äöüÄÖÜß."
        assert persistent_result["records"] == [{
            "order_id": persistent_result["state"]["orders"][0]["order_id"],
            "type": "sonstiges",
            "complete": True,
            "data": persistent_result["state"]["orders"][0]["fields"],
            "zusammenfassung": utf8_text + ".",
            "adapter": "kienzlefon_spool",
            "call_id": "call-synthetic-1",
        }]
        assert committed_orders == [
            (f"text-chat-{persistent_session_id}", "", utf8_text)
        ]
        assert text_runtime.hangup(persistent_session_id)["records"] \
            == persistent_result["records"]
        assert len(committed_orders) == 1
    finally:
        globals()["call_llm"] = original_call_llm
        globals()["commit_order"] = original_commit_order

    text_debug = TextDebugHub(TextTestConfig())  # type: ignore[arg-type]
    public_id, public_debug = text_debug.subscribe(True, False)
    sensitive_id, sensitive_debug = text_debug.subscribe(True, True)
    text_debug.emit(
        "chat_llm_end",
        {"reply_chars": 6},
        {"reply": "Müller"},
    )
    assert "reply" not in public_debug.events.get_nowait()
    assert sensitive_debug.events.get_nowait()["reply"] == "Müller"
    text_debug.unsubscribe(public_id)
    text_debug.unsubscribe(sensitive_id)

    class AudioHeaders:
        def __init__(self, values: Mapping[str, str]) -> None:
            self.values = {name.lower(): value for name, value in values.items()}

        def getheader(self, name: str, default: str | None = None) -> str | None:
            return self.values.get(name.lower(), default)

    qwen_headers = AudioHeaders(
        {
            "Content-Type": "audio/pcm",
            "X-Sample-Rate": "24000",
            "X-Channels": "1",
            "X-Sample-Format": "s16le",
        }
    )
    assert _validate_audio_headers(qwen_headers, 24000, True) == 24000  # type: ignore[arg-type]
    try:
        _validate_audio_headers(  # type: ignore[arg-type]
            AudioHeaders({"Content-Type": "audio/pcm"}), 24000, True
        )
    except ProtocolError:
        pass
    else:
        raise AssertionError("incomplete Qwen PCM headers accepted")
    assert _validate_audio_headers(  # type: ignore[arg-type]
        AudioHeaders({"Content-Type": "application/octet-stream"}), 22050, False
    ) == 22050

    websocket_payload = b'{"ok":true}'
    websocket = WebSocketClient("ws://127.0.0.1/mock", 1.0)
    websocket.sock = object()  # type: ignore[assignment]
    websocket.buffer.extend(bytes([0x81, len(websocket_payload)]) + websocket_payload)
    assert websocket.recv_json() == {"ok": True}
    masked = WebSocketClient("ws://127.0.0.1/mock", 1.0)
    masked.sock = object()  # type: ignore[assignment]
    masked.buffer.extend(b"\x81\x80")
    try:
        masked.recv_json()
    except ProtocolError:
        pass
    else:
        raise AssertionError("masked WebSocket server frame accepted")

    terminal_queue: asyncio.Queue[bytes | BaseException | None] = asyncio.Queue()
    terminal_queue.put_nowait(b"old audio")
    terminal_queue.put_nowait(ProtocolError("synthetic_input_failure"))
    AgentServer.clear_audio_queue(terminal_queue)
    assert isinstance(terminal_queue.get_nowait(), ProtocolError)
    assert terminal_queue.empty()

    payload = b"\0" * TELEPHONY_FRAME_BYTES
    packet = bytes([AUDIO_TYPE_SLIN16]) + struct.pack("!H", len(payload)) + payload
    assert packet[:3] == b"\x12\x02\x80" and len(packet) == 643

    class DebugConfig:
        slot_count = 3
        debug_allow_sensitive_console = True
        tts_backend = "qwen"
        performance_enabled = False
        performance_log_file = MANAGED_PERFORMANCE_LOG
        performance_max_bytes = 10485760
        performance_backup_count = 5
        energy_threshold = 520
        preroll_ms = 300
        speech_start_ms = 120
        speech_end_ms = 500

        @staticmethod
        def slot_id(index: int) -> str:
            return f"ai-slot-{index:02d}"

    class MemoryWriter:
        def __init__(self) -> None:
            self.buffer = bytearray()

        def write(self, data: bytes) -> None:
            self.buffer.extend(data)

        async def drain(self) -> None:
            return None

    async def media_transport_test() -> None:
        server = AgentServer(DebugConfig(), 0)  # type: ignore[arg-type]
        reader = asyncio.StreamReader()
        half_frame = b"\x01\x00" * (TELEPHONY_FRAME_BYTES // 4)
        reader.feed_data(
            bytes([AUDIO_TYPE_SLIN16])
            + struct.pack("!H", len(half_frame))
            + half_frame
            + bytes([DTMF_TYPE])
            + struct.pack("!H", 1)
            + b"5"
            + bytes([AUDIO_TYPE_SLIN16])
            + struct.pack("!H", len(half_frame))
            + half_frame
            + bytes([TERMINATE_TYPE, 0, 0])
        )
        reader.feed_eof()
        queue: asyncio.Queue[bytes | BaseException | None] = asyncio.Queue(
            maxsize=4
        )
        await server.audio_reader(reader, queue)
        assert queue.get_nowait() == half_frame + half_frame
        assert queue.get_nowait() is None and queue.empty()

        invalid_reader = asyncio.StreamReader()
        invalid_reader.feed_data(b"\x10\x00\x02\x00\x00")
        invalid_reader.feed_eof()
        invalid_queue: asyncio.Queue[
            bytes | BaseException | None
        ] = asyncio.Queue(maxsize=2)
        await server.audio_reader(invalid_reader, invalid_queue)
        invalid_result = invalid_queue.get_nowait()
        assert isinstance(invalid_result, ProtocolError)
        assert str(invalid_result) == "audiosocket_input_failed"

        output_pcm = bytes(index % 251 for index in range(1000))

        def fake_stream_tts(
            _config: AgentConfig,
            _text: str,
            backend: str,
            emit: Callable[[bytes], None],
            debug: Callable[[str, Mapping[str, Any]], None] | None = None,
        ) -> None:
            assert backend == "qwen"
            if debug is not None:
                debug(
                    "tts_media_format",
                    {
                        "audiosocket_format": TELEPHONY_FORMAT,
                        "audiosocket_type": f"0x{AUDIO_TYPE_SLIN16:02x}",
                    },
                )
            emit(output_pcm[:301])
            emit(output_pcm[301:])

        writer = MemoryWriter()
        original_stream_tts = globals()["stream_tts"]
        globals()["stream_tts"] = fake_stream_tts
        try:
            tts_metrics = await server.speak(
                "synthetic self-test",
                writer,  # type: ignore[arg-type]
                asyncio.Lock(),
                allow_fallback=False,
                purpose="self_test",
            )
        finally:
            globals()["stream_tts"] = original_stream_tts

        output_frames: list[bytes] = []
        cursor = 0
        while cursor < len(writer.buffer):
            assert writer.buffer[cursor] == AUDIO_TYPE_SLIN16
            length = struct.unpack("!H", writer.buffer[cursor + 1 : cursor + 3])[0]
            cursor += 3
            output_frames.append(bytes(writer.buffer[cursor : cursor + length]))
            cursor += length
        assert cursor == len(writer.buffer)
        assert len(output_frames) == 2
        assert all(len(frame) == TELEPHONY_FRAME_BYTES for frame in output_frames)
        assert output_frames[0] == output_pcm[:TELEPHONY_FRAME_BYTES]
        remaining = output_pcm[TELEPHONY_FRAME_BYTES:]
        assert output_frames[1] == remaining + b"\0" * (
            TELEPHONY_FRAME_BYTES - len(remaining)
        )
        assert tts_metrics.backend == "qwen"
        assert tts_metrics.first_audio_generated_ms is not None
        assert tts_metrics.first_audio_written_ms is not None
        assert tts_metrics.first_audio_written_monotonic_ns is not None
        assert tts_metrics.audio_ms == len(output_pcm) * 1000 // (
            TELEPHONY_RATE * PCM_WIDTH
        )

    asyncio.run(media_transport_test())

    debug_server = AgentServer(DebugConfig(), 0)  # type: ignore[arg-type]
    public_queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=2)
    sensitive_queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=2)
    debug_server.debug_subscribers = {
        1: DebugSubscriber(public_queue, False),
        2: DebugSubscriber(sensitive_queue, True),
    }
    debug_server.emit_debug(
        "asr_confirmed", {"chars": 6}, {"text": "privat"}
    )
    assert "text" not in public_queue.get_nowait()
    assert sensitive_queue.get_nowait()["text"] == "privat"
    try:
        debug_server._debug_event("invalid_public", {"text": "privat"})
    except AgentError as error:
        assert str(error) == "sensitive_debug_field_in_public_event"
    else:
        raise AssertionError("sensitive field accepted in public debug event")
    debug_server.debug_subscribers = {1: DebugSubscriber(public_queue, False)}
    for number in range(3):
        debug_server.emit_debug("queue_test", {"number": number})
    assert public_queue.qsize() == 2
    public_queue.get_nowait()
    assert public_queue.get_nowait()["dropped_before"] == 1

    class ClaimConfig:
        slot_count = 3
        performance_enabled = False
        performance_log_file = MANAGED_PERFORMANCE_LOG
        performance_max_bytes = 10485760
        performance_backup_count = 5

        @staticmethod
        def slot_id(index: int) -> str:
            return f"ai-slot-{index:02d}"

    async def claim_test() -> None:
        server = AgentServer(ClaimConfig(), 0)  # type: ignore[arg-type]
        status = await server.status_payload()
        assert status["audiosocket_format"] == "slin16"
        assert status["audiosocket_type"] == "0x12"
        assert status["audiosocket_sample_rate"] == 16000
        assert status["frame_ms"] == 20 and status["frame_bytes"] == 640
        message = {
            "protocol": PROTOCOL,
            "slot_id": "ai-slot-00",
            "call_uuid": str(uuid.uuid4()),
            "request_id": "request-01",
            "lease_id": str(uuid.uuid4()),
            "caller_id": "",
        }
        assert (await server.claim(message))["ok"] is True
        second = dict(message, call_uuid=str(uuid.uuid4()), lease_id=str(uuid.uuid4()))
        assert (await server.claim(second))["ok"] is False
        next(iter(server.pending.values())).expires_at = time.monotonic() - 1.0
        assert server._cleanup_claims() is True and not server.pending

    asyncio.run(claim_test())

    class StreamConfig:
        slot_count = 3
        debug_allow_sensitive_console = True
        performance_enabled = False
        performance_log_file = MANAGED_PERFORMANCE_LOG
        performance_max_bytes = 10485760
        performance_backup_count = 5

        @staticmethod
        def slot_id(index: int) -> str:
            return f"ai-slot-{index:02d}"

    async def debug_stream_test() -> None:
        agents = [
            AgentServer(StreamConfig(), index)  # type: ignore[arg-type]
            for index in range(3)
        ]
        for agent in agents:
            agent.peer_uid = lambda _writer: 0  # type: ignore[method-assign]
        clients: list[tuple[asyncio.StreamReader, asyncio.StreamWriter]] = []
        handlers: list[asyncio.Task[None]] = []

        async def connect(
            server: AgentServer, show_text: bool
        ) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
            client_socket, server_socket = socket.socketpair()
            server_reader, server_writer = await asyncio.open_connection(
                sock=server_socket
            )
            handlers.append(
                asyncio.create_task(server.control(server_reader, server_writer))
            )
            reader, writer = await asyncio.open_connection(sock=client_socket)
            writer.write(
                json.dumps({
                    "command": "debug_subscribe",
                    "show_text": show_text,
                }).encode() + b"\n"
            )
            await writer.drain()
            return reader, writer

        try:
            for index, server in enumerate(agents):
                reader, writer = await connect(server, index == 0)
                acknowledgement = json.loads(await reader.readline())
                snapshot = json.loads(await reader.readline())
                assert acknowledgement["protocol"] == DEBUG_PROTOCOL
                assert acknowledgement["show_text"] is (index == 0)
                assert snapshot["event"] == "slot_status"
                assert snapshot["audiosocket_format"] == "slin16"
                assert snapshot["audiosocket_type"] == "0x12"
                assert snapshot["audiosocket_sample_rate"] == 16000
                assert snapshot["frame_ms"] == 20
                assert snapshot["frame_bytes"] == 640
                clients.append((reader, writer))
            for server in agents:
                server.emit_debug(
                    "asr_partial", {"chars": 6}, {"text": "privat"}
                )
            for index, (reader, _writer) in enumerate(clients):
                while True:
                    event = json.loads(await asyncio.wait_for(reader.readline(), 1.0))
                    if event["event"] == "asr_partial":
                        break
                assert (event.get("text") == "privat") is (index == 0)

            clients[0][1].close()
            await clients[0][1].wait_closed()
            agents[0].emit_debug("disconnect_probe", {})
            await asyncio.sleep(0.05)
            reconnect_reader, reconnect_writer = await connect(agents[0], False)
            assert json.loads(await reconnect_reader.readline())["ok"] is True
            assert json.loads(await reconnect_reader.readline())["event"] == "slot_status"
            reconnect_writer.close()
            await reconnect_writer.wait_closed()
            clients = clients[1:]
        finally:
            for _reader, writer in clients:
                writer.close()
                with contextlib.suppress(Exception):
                    await writer.wait_closed()
            for agent in agents:
                agent.stopping.set()
                agent.emit_debug("test_stopping", {})
            if handlers:
                await asyncio.wait(handlers, timeout=1.0)

    asyncio.run(debug_stream_test())

    path_config = object.__new__(AgentConfig)
    object.__setattr__(path_config, "runtime_directory", Path("/run/kienzlefon-ai-asterisk-backend"))
    assert path_config.control_socket(0) == Path(
        "/run/kienzlefon-ai-asterisk-backend/slot-0/control.sock"
    )
    assert len({path_config.control_socket(index) for index in range(3)}) == 3

    registration_output = """
 <Registration/ServerURI..............................> <Auth..........> <Status.......>
 =========================================================================================
 ai-slot-01-registration/sip:10.88.0.1:5060 ai-slot-01-auth Unregistered
 ai-slot-00-registration/sip:10.88.0.1:5060 ai-slot-00-auth Registered

 ParameterName : ParameterValue
 ====================================================
 client_uri : sip:8810@10.88.0.1:5060
 """
    assert AgentServer.pjsip_registration_status(
        registration_output, "ai-slot-00-registration"
    ) == "Registered"
    assert AgentServer.pjsip_registration_status(
        registration_output, "ai-slot-01-registration"
    ) == "Unregistered"
    assert AgentServer.pjsip_registration_status(
        registration_output, "ai-slot-02-registration"
    ) is None
    for rejected_state in ("Unregistered", "Rejected", "Stopped"):
        output = (
            "ai-slot-00-registration/sip:10.88.0.1:5060 "
            f"ai-slot-00-auth {rejected_state}\n"
        )
        assert AgentServer.pjsip_registration_status(
            output, "ai-slot-00-registration"
        ) == rejected_state
    print("agent self-test: ok")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=(
            "serve", "serve-text", "guard", "status", "commit-helper", "check-config",
            "self-test", "version", "prepare-filler", "check-filler",
        ),
    )
    parser.add_argument("--config")
    parser.add_argument("--slot-index", type=int)
    parser.add_argument("--filler-output")
    return parser.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = parse_arguments()
    if args.command == "version":
        print(VERSION)
        return 0
    if args.command == "self-test":
        return self_test()
    if not args.config:
        raise SystemExit("--config is required")
    config = load_config(args.config)
    if args.command in {"prepare-filler", "check-filler"}:
        try:
            if args.command == "prepare-filler":
                if not args.filler_output:
                    raise ProtocolError("filler_output_required")
                prepare_filler_clips(config, Path(args.filler_output))
            else:
                if config.filler_enabled:
                    load_filler_clips(config)
                    print("filler clips: valid")
                else:
                    print("filler clips: disabled")
            return 0
        except Exception as error:
            # Never print backend response bodies or configuration values.
            print("FILLER_FAIL code=" + diagnostic_error_code(error), file=sys.stderr)
            return 1
    if args.command == "check-config":
        print("configuration valid")
        return 0
    if args.command == "commit-helper":
        return commit_helper(config)
    if args.command == "serve-text":
        return serve_text(config)
    if args.slot_index is None or not 0 <= args.slot_index < config.slot_count:
        raise SystemExit("--slot-index must be 0, 1 or 2")
    if args.command == "guard":
        return guard(config, args.slot_index)
    if args.command == "status":
        try:
            response = unix_command(
                config.control_socket(args.slot_index), {"command": "status"}
            )
        except Exception as error:
            print(json.dumps({
                "ok": False,
                "reason": "control_unavailable",
                "code": diagnostic_error_code(error),
            }, separators=(",", ":")))
            return 1
        print(json.dumps(response, separators=(",", ":")))
        return 0 if response.get("ok") is True else 1
    return asyncio.run(serve(config, args.slot_index))


if __name__ == "__main__":
    raise SystemExit(main())
PY
  chmod 0755 "$temp"
  mv -f "$temp" "$target"
}

write_tts_guard() {
  local target="$1"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<'PY'
"""Deterministic German normalization for Kienzlefon TTS.

IMPORTANT:
Only apply this to text sent to TTS.
Never apply it to JSON, stored fields or Telepraxis payloads.
"""

from __future__ import annotations

import re
from datetime import date


MONTHS = {
    1: "Januar",
    2: "Februar",
    3: "März",
    4: "April",
    5: "Mai",
    6: "Juni",
    7: "Juli",
    8: "August",
    9: "September",
    10: "Oktober",
    11: "November",
    12: "Dezember",
}

MONTH_NUMBERS = {
    "januar": 1,
    "februar": 2,
    "märz": 3,
    "maerz": 3,
    "april": 4,
    "mai": 5,
    "juni": 6,
    "juli": 7,
    "august": 8,
    "september": 9,
    "oktober": 10,
    "november": 11,
    "dezember": 12,
}

ONES = {
    0: "null",
    1: "eins",
    2: "zwei",
    3: "drei",
    4: "vier",
    5: "fünf",
    6: "sechs",
    7: "sieben",
    8: "acht",
    9: "neun",
}

TEENS = {
    10: "zehn",
    11: "elf",
    12: "zwölf",
    13: "dreizehn",
    14: "vierzehn",
    15: "fünfzehn",
    16: "sechzehn",
    17: "siebzehn",
    18: "achtzehn",
    19: "neunzehn",
}

TENS = {
    20: "zwanzig",
    30: "dreißig",
    40: "vierzig",
    50: "fünfzig",
    60: "sechzig",
    70: "siebzig",
    80: "achtzig",
    90: "neunzig",
}

UNITS = {
    "mg": "Milligramm",
    "g": "Gramm",
    "kg": "Kilogramm",
    "µg": "Mikrogramm",
    "μg": "Mikrogramm",
    "ug": "Mikrogramm",
    "mcg": "Mikrogramm",
    "ml": "Milliliter",
    "l": "Liter",
    "mmol/l": "Millimol pro Liter",
    "mg/dl": "Milligramm pro Deziliter",
}


DATE_RE = re.compile(
    r"(?<!\d)"
    r"(?P<prefix>(?:am|vom)\s+)?"
    r"(?P<day>\d{1,2})[./-]"
    r"(?P<month>\d{1,2})[./-]"
    r"(?P<year>\d{4})"
    r"(?!\d)",
    re.IGNORECASE,
)

DATE_NAME_RE = re.compile(
    r"(?<!\d)"
    r"(?P<prefix>(?:am|vom)\s+)?"
    r"(?P<day>\d{1,2})\.\s*"
    r"(?P<month>"
    r"Januar|Februar|März|Maerz|April|Mai|Juni|Juli|"
    r"August|September|Oktober|November|Dezember"
    r")\s+"
    r"(?P<year>\d{4})"
    r"(?!\d)",
    re.IGNORECASE,
)

TIME_COLON_RE = re.compile(
    r"(?<!\d)"
    r"(?P<hour>[01]?\d|2[0-3]):"
    r"(?P<minute>[0-5]\d)"
    r"(?:\s*Uhr)?\b",
    re.IGNORECASE,
)

# Punktnotation absichtlich nur mit "Uhr".
# "10.30" allein wird nicht als Uhrzeit interpretiert.
TIME_DOT_RE = re.compile(
    r"(?<!\d)"
    r"(?P<hour>[01]?\d|2[0-3])\."
    r"(?P<minute>[0-5]\d)"
    r"\s*Uhr\b",
    re.IGNORECASE,
)

TIME_UHR_RE = re.compile(
    r"(?<!\d)"
    r"(?P<hour>[01]?\d|2[0-3])\s*Uhr"
    r"(?:\s+(?P<minute>[0-5]?\d))?"
    r"\b",
    re.IGNORECASE,
)

PHONE_CONTEXT_RE = re.compile(
    r"(?P<label>"
    r"\b(?:Telefonnummer|Rufnummer|Handynummer|Telefon)\b"
    r"(?:\s+(?:ist|lautet))?\s*[:=]?\s*"
    r")"
    r"(?P<number>\+?\d(?:[\s()/.-]*\d){4,})"
    r"(?!\w)",
    re.IGNORECASE,
)

PHONE_RE = re.compile(
    r"(?<!\w)"
    r"(?:\+49|0)"
    r"(?:[\s()/.-]*\d){5,}"
    r"(?!\w)"
)

DOSE_RE = re.compile(
    r"(?<!\w)"
    r"(?P<value>\d+(?:[,.]\d+)?)\s*"
    r"(?P<unit>"
    r"mmol/l|mg/dl|mcg|µg|μg|ug|mg|kg|ml|g|l"
    r")\b",
    re.IGNORECASE,
)


def number_de(n: int) -> str:
    if n < 0:
        return "minus " + number_de(-n)

    if n < 10:
        return ONES[n]

    if n < 20:
        return TEENS[n]

    if n < 100:
        tens = (n // 10) * 10
        rest = n % 10

        if rest == 0:
            return TENS[tens]

        one = "ein" if rest == 1 else ONES[rest]
        return one + "und" + TENS[tens]

    if n < 1000:
        hundreds = n // 100
        rest = n % 100

        prefix = (
            "einhundert"
            if hundreds == 1
            else ONES[hundreds] + "hundert"
        )

        return prefix if rest == 0 else prefix + number_de(rest)

    if n < 1_000_000:
        thousands = n // 1000
        rest = n % 1000

        prefix = (
            "eintausend"
            if thousands == 1
            else number_de(thousands) + "tausend"
        )

        return prefix if rest == 0 else prefix + number_de(rest)

    # Extrem große Zahlen lieber unverändert lassen.
    return str(n)


def year_de(year: int) -> str:
    # 1943 -> neunzehnhundertdreiundvierzig
    # 2002 -> zweitausendzwei
    if 1100 <= year <= 1999:
        century = year // 100
        rest = year % 100

        result = number_de(century) + "hundert"

        if rest:
            result += number_de(rest)

        return result

    return number_de(year)


def ordinal_day(day: int, dative: bool = False) -> str:
    irregular = {
        1: "erst",
        3: "dritt",
        7: "siebt",
        8: "acht",
    }

    if day in irregular:
        return irregular[day] + ("en" if dative else "er")

    if day < 20:
        return number_de(day) + ("ten" if dative else "ter")

    return number_de(day) + ("sten" if dative else "ster")


def digits_de(value: str) -> str:
    spoken: list[str] = []

    for char in value:
        if char == "+":
            spoken.append("plus")
        elif char.isdigit():
            spoken.append(ONES[int(char)])

    return " ".join(spoken)


def decimal_de(value: str) -> str:
    value = value.replace(".", ",")

    if "," not in value:
        return number_de(int(value))

    whole, fraction = value.split(",", 1)

    # Nachkommastellen absichtlich ziffernweise:
    # 47,05 -> siebenundvierzig Komma null fünf
    fraction_spoken = " ".join(
        ONES[int(char)]
        for char in fraction
    )

    return (
        f"{number_de(int(whole))} "
        f"Komma {fraction_spoken}"
    )


def _normalize_numeric_date(match: re.Match[str]) -> str:
    prefix = match.group("prefix") or ""
    day = int(match.group("day"))
    month = int(match.group("month"))
    year = int(match.group("year"))

    try:
        date(year, month, day)
    except ValueError:
        return match.group(0)

    dative = bool(prefix)

    return (
        f"{prefix}"
        f"{ordinal_day(day, dative=dative)} "
        f"{MONTHS[month]} "
        f"{year_de(year)}"
    )


def _normalize_named_date(match: re.Match[str]) -> str:
    prefix = match.group("prefix") or ""
    day = int(match.group("day"))
    month_name = match.group("month")
    month = MONTH_NUMBERS[month_name.casefold()]
    year = int(match.group("year"))

    try:
        date(year, month, day)
    except ValueError:
        return match.group(0)

    dative = bool(prefix)

    return (
        f"{prefix}"
        f"{ordinal_day(day, dative=dative)} "
        f"{MONTHS[month]} "
        f"{year_de(year)}"
    )


def _normalize_time(match: re.Match[str]) -> str:
    hour = int(match.group("hour"))
    minute = int(match.group("minute"))

    if minute == 0:
        return f"{number_de(hour)} Uhr"

    return (
        f"{number_de(hour)} Uhr "
        f"{number_de(minute)}"
    )


def _normalize_uhr_time(match: re.Match[str]) -> str:
    hour = int(match.group("hour"))
    minute_raw = match.group("minute")

    if minute_raw is None:
        return f"{number_de(hour)} Uhr"

    minute = int(minute_raw)

    if minute == 0:
        return f"{number_de(hour)} Uhr"

    return (
        f"{number_de(hour)} Uhr "
        f"{number_de(minute)}"
    )


def _normalize_dose(match: re.Match[str]) -> str:
    value = match.group("value")
    unit = UNITS[match.group("unit").casefold()]

    return f"{decimal_de(value)} {unit}"


def normalize_tts_text(text: str) -> str:
    """Return deterministic TTS-friendly German text."""

    if not isinstance(text, str) or not text:
        return text

    # Wichtig: spezifische Formate immer vor allgemeinen Zahlen.

    # 1. Datum
    text = DATE_RE.sub(_normalize_numeric_date, text)
    text = DATE_NAME_RE.sub(_normalize_named_date, text)

    # 2. Uhrzeiten
    text = TIME_COLON_RE.sub(_normalize_time, text)
    text = TIME_DOT_RE.sub(_normalize_time, text)
    text = TIME_UHR_RE.sub(_normalize_uhr_time, text)

    # 3. Telefonnummern mit explizitem Kontext
    text = PHONE_CONTEXT_RE.sub(
        lambda m: (
            m.group("label")
            + digits_de(m.group("number"))
        ),
        text,
    )

    # 4. Normale deutsche Telefonnummern
    text = PHONE_RE.sub(
        lambda m: digits_de(m.group(0)),
        text,
    )

    # Wichtige Notruf-/Servicenummern ebenfalls einzeln.
    text = re.sub(
        r"(?<!\d)116\s*117(?!\d)",
        lambda m: digits_de(m.group(0)),
        text,
    )

    text = re.sub(
        r"(?<!\d)(?:110|112)(?!\d)",
        lambda m: digits_de(m.group(0)),
        text,
    )

    # 5. Medizinische Mengen
    text = DOSE_RE.sub(_normalize_dose, text)

    # 6. Prozent
    text = re.sub(
        r"(?<!\d)(\d+(?:[,.]\d+)?)\s*%",
        lambda m: (
            decimal_de(m.group(1))
            + " Prozent"
        ),
        text,
    )

    # 7. Deutsche Dezimalzahlen
    text = re.sub(
        r"(?<!\d)\d+,\d+(?!\d)",
        lambda m: decimal_de(m.group(0)),
        text,
    )

    # 8. Übrige ganze Zahlen als Kardinalzahlen.
    #
    # Zahlen in unbekannten Punktformaten wie "10.30"
    # werden bewusst nicht auseinandergerissen.
    text = re.sub(
        r"(?<!\d[.,])"
        r"(?<![\w\d])"
        r"\d+"
        r"(?![\w\d]|\.\d|,\d)",
        lambda m: number_de(int(m.group(0))),
        text,
    )

    return re.sub(r"[ \t]+", " ", text)


__all__ = ["normalize_tts_text"]
PY
  chmod 0644 "$temp"
  mv -f "$temp" "$target"
}

write_chat_client() {
  local target="$1"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<'PY'
#!/usr/bin/env python3
"""Interactive local terminal client for the Kienzlefon chat channel."""

from __future__ import annotations

import argparse
import ipaddress
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from typing import Any, Callable, Mapping, TextIO


VERSION = "2.5.1"
PROTOCOL = "kienzlefon-ai-text-v1"
DEFAULT_BACKEND_URL = "http://127.0.0.1:8300"
DEFAULT_TIMEOUT_SECONDS = 120.0
MAX_RESPONSE_BYTES = 16 * 1024 * 1024
MAX_TURN_CHARACTERS = 12000


class ChatClientError(Exception):
    """Base class for expected, safely reportable client errors."""


class ConfigurationError(ChatClientError):
    pass


class TransportError(ChatClientError):
    pass


class ContractError(ChatClientError):
    pass


def strict_json_loads(value: str) -> Any:
    def reject_constant(constant: str) -> None:
        raise ValueError(f"non-standard JSON constant: {constant}")

    return json.loads(value, parse_constant=reject_constant)


def compact_json(value: Mapping[str, Any]) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        separators=(",", ":"),
    ).encode("utf-8")


def pretty_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        indent=2,
        sort_keys=True,
    )


def assert_loopback_base_url(value: str) -> str:
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ConfigurationError("--backend-url muss eine HTTP(S)-URL sein")
    if parsed.username is not None or parsed.password is not None:
        raise ConfigurationError("--backend-url darf keine Zugangsdaten enthalten")
    if parsed.query or parsed.fragment or parsed.path not in {"", "/"}:
        raise ConfigurationError("--backend-url muss eine reine Basis-URL sein")
    hostname = parsed.hostname
    if hostname != "localhost":
        try:
            address = ipaddress.ip_address(hostname)
        except ValueError as exc:
            raise ConfigurationError(
                "--backend-url muss einen Loopback-Host verwenden"
            ) from exc
        if not address.is_loopback:
            raise ConfigurationError(
                "--backend-url muss einen Loopback-Host verwenden"
            )
    try:
        parsed.port
    except ValueError as exc:
        raise ConfigurationError("--backend-url enthält einen ungültigen Port") from exc
    return value.rstrip("/")


def console_safe_text(value: str) -> str:
    return "".join(
        character
        if character in "\n\t" or character.isprintable()
        else f"\\u{ord(character):04x}"
        for character in value
    )


@dataclass(frozen=True)
class HTTPResponse:
    status: int
    data: Any


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: Any,
        code: int,
        msg: str,
        headers: Mapping[str, str],
        newurl: str,
    ) -> None:
        return None


class JSONHTTPClient:
    def __init__(self, timeout: float) -> None:
        self.timeout = timeout
        self.opener = urllib.request.build_opener(NoRedirectHandler())

    def request(
        self,
        operation: str,
        method: str,
        url: str,
        payload: Mapping[str, Any] | None = None,
    ) -> HTTPResponse:
        body = None
        headers = {"Accept": "application/json"}
        if payload is not None:
            body = compact_json(payload)
            headers["Content-Type"] = "application/json; charset=utf-8"
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                raw = response.read(MAX_RESPONSE_BYTES + 1)
                status = int(response.status)
        except urllib.error.HTTPError as exc:
            status = int(exc.code)
            try:
                exc.read(MAX_RESPONSE_BYTES + 1)
            finally:
                exc.close()
            raise TransportError(f"{operation}: HTTP {status}") from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise TransportError(f"{operation}: {type(exc).__name__}") from exc
        if len(raw) > MAX_RESPONSE_BYTES:
            raise TransportError(f"{operation}: Antwort überschreitet das Größenlimit")
        try:
            response_text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise TransportError(f"{operation}: Antwort ist nicht UTF-8") from exc
        try:
            data = strict_json_loads(response_text)
        except (json.JSONDecodeError, ValueError) as exc:
            raise TransportError(f"{operation}: Antwort ist kein gültiges JSON") from exc
        return HTTPResponse(status, data)


class RuntimeClient:
    def __init__(self, backend_url: str, timeout: float) -> None:
        self.backend_url = backend_url
        self.http = JSONHTTPClient(timeout)

    def url(self, path: str) -> str:
        return self.backend_url + path

    def health(self) -> HTTPResponse:
        return self.http.request("health", "GET", self.url("/health"))

    def create_session(self) -> HTTPResponse:
        return self.http.request(
            "create_session",
            "POST",
            self.url("/v1/dialog/sessions"),
            {
                "channel": "chat",
                "recording_mode": "spool",
                "caller_id": None,
                "environment": {"within_phone_hours": False},
            },
        )

    def turn(self, session_id: str, text: str) -> HTTPResponse:
        return self.http.request(
            "turn",
            "POST",
            self.url(f"/v1/dialog/sessions/{session_id}/turn"),
            {"text": text},
        )

    def hangup(self, session_id: str) -> HTTPResponse:
        return self.http.request(
            "hangup",
            "POST",
            self.url(f"/v1/dialog/sessions/{session_id}/hangup"),
            {},
        )

    def delete(self, session_id: str) -> HTTPResponse:
        return self.http.request(
            "delete",
            "DELETE",
            self.url(f"/v1/dialog/sessions/{session_id}"),
        )


def require_object(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ContractError(f"{label}: Antwort ist kein JSON-Objekt")
    return value


def validate_health(response: HTTPResponse) -> str:
    if response.status != 200:
        raise ContractError("health: unerwarteter HTTP-Status")
    data = require_object(response.data, "health")
    if data.get("ok") is not True or not isinstance(data.get("version"), str):
        raise ContractError("health: ungültiger Runtime-Status")
    return data["version"]


def validate_session_created(response: HTTPResponse) -> str:
    if response.status != 201:
        raise ContractError("create_session: unerwarteter HTTP-Status")
    data = require_object(response.data, "create_session")
    if data.get("protocol") != PROTOCOL or data.get("channel") != "chat":
        raise ContractError("create_session: Protokoll oder Kanal stimmt nicht")
    session_id = data.get("session_id")
    if not isinstance(session_id, str):
        raise ContractError("create_session: Session-ID fehlt")
    try:
        uuid.UUID(session_id)
    except ValueError as exc:
        raise ContractError("create_session: Session-ID ist ungültig") from exc
    if data.get("recording_mode") != "spool":
        raise ContractError("create_session: persistenter Spool-Modus ist nicht aktiv")
    if data.get("terminal") is not False:
        raise ContractError("create_session: neue Session ist bereits terminal")
    if data.get("introduction_already_handled") is not True:
        raise ContractError("create_session: Einführungsstatus ist ungültig")
    return session_id


def validate_common_response(
    response: HTTPResponse,
    session_id: str,
    *,
    operation: str,
) -> Mapping[str, Any]:
    if response.status != 200:
        raise ContractError(f"{operation}: unerwarteter HTTP-Status")
    data = require_object(response.data, operation)
    if data.get("protocol") != PROTOCOL:
        raise ContractError(f"{operation}: Protokoll stimmt nicht")
    if data.get("session_id") != session_id or data.get("channel") != "chat":
        raise ContractError(f"{operation}: Session oder Kanal stimmt nicht")
    if data.get("recording_mode") != "spool":
        raise ContractError(f"{operation}: persistenter Spool-Modus ging verloren")
    if not isinstance(data.get("terminal"), bool):
        raise ContractError(f"{operation}: Terminalstatus ist ungültig")
    if not isinstance(data.get("state"), Mapping):
        raise ContractError(f"{operation}: Dialogzustand fehlt")
    if not isinstance(data.get("records"), list):
        raise ContractError(f"{operation}: Records sind ungültig")
    action_result = data.get("action_result")
    if action_result is not None and not isinstance(action_result, Mapping):
        raise ContractError(f"{operation}: Aktionsergebnis ist ungültig")
    return data


def validate_turn(response: HTTPResponse, session_id: str) -> Mapping[str, Any]:
    data = validate_common_response(response, session_id, operation="turn")
    reply = data.get("reply")
    if not isinstance(reply, str) or not reply.strip():
        raise ContractError("turn: Antworttext fehlt")
    if "raw_response" not in data:
        raise ContractError("turn: Rohantwort fehlt")
    if not isinstance(data.get("normalized_response"), Mapping):
        raise ContractError("turn: normalisierte Antwort fehlt")
    if not isinstance(data.get("repairs"), list):
        raise ContractError("turn: Reparaturliste fehlt")
    return data


def validate_hangup(response: HTTPResponse, session_id: str) -> Mapping[str, Any]:
    data = validate_common_response(response, session_id, operation="hangup")
    if data.get("terminal") is not True:
        raise ContractError("hangup: Session ist nicht terminal")
    return data


def validate_delete(response: HTTPResponse) -> None:
    if response.status != 200:
        raise ContractError("delete: unerwarteter HTTP-Status")
    data = require_object(response.data, "delete")
    if data.get("ok") is not True:
        raise ContractError("delete: Session wurde nicht bestätigt gelöscht")


class ChatSession:
    def __init__(self, runtime: RuntimeClient) -> None:
        self.runtime = runtime
        self.session_id: str | None = None
        self.terminal = False
        self.last_turn: Mapping[str, Any] | None = None
        self.last_records: list[Any] = []

    def open(self) -> str:
        validate_health(self.runtime.health())
        self.session_id = validate_session_created(self.runtime.create_session())
        return self.session_id

    def send(self, text: str) -> Mapping[str, Any]:
        if self.session_id is None:
            raise ContractError("keine aktive Session")
        data = validate_turn(self.runtime.turn(self.session_id, text), self.session_id)
        self.last_turn = data
        self.last_records = list(data["records"])
        self.terminal = bool(data["terminal"])
        return data

    def close(self) -> tuple[bool, list[Any]]:
        if self.session_id is None:
            return False, list(self.last_records)
        session_id = self.session_id
        if not self.terminal:
            hangup = validate_hangup(
                self.runtime.hangup(session_id), session_id
            )
            self.last_records = list(hangup["records"])
            self.terminal = True
        validate_delete(self.runtime.delete(session_id))
        self.session_id = None
        return True, list(self.last_records)


HELP_TEXT = """Befehle:
  /help    diese Hilfe anzeigen
  /state   bestätigten Dialogzustand des letzten Turns anzeigen
  /raw     unveränderte LLM-Rohantwort des letzten Turns anzeigen
  /records erzeugte persistente Aufträge dieser Session anzeigen
  /hangup  Session abschließen, löschen und Client beenden
  /quit    Session abschließen, löschen und Client beenden"""


def write_line(stream: TextIO, value: str = "") -> None:
    stream.write(value + "\n")
    stream.flush()


def write_prompt(stream: TextIO) -> None:
    stream.write("Sie> ")
    stream.flush()


def show_last_value(
    stream: TextIO,
    last_turn: Mapping[str, Any] | None,
    field: str,
    empty_message: str,
) -> None:
    if last_turn is None:
        write_line(stream, empty_message)
        return
    write_line(stream, pretty_json(last_turn[field]))


def write_record_summary(stream: TextIO, records: list[Any]) -> None:
    persistent = [
        record
        for record in records
        if isinstance(record, Mapping)
        and record.get("adapter") == "kienzlefon_spool"
    ]
    if not persistent:
        write_line(stream, "Keine vollständigen JSON-Aufträge erzeugt.")
        return
    write_line(stream, "Erzeugte JSON-Aufträge:")
    for record in persistent:
        write_line(
            stream,
            "  call_id="
            + console_safe_text(str(record.get("call_id", "unbekannt")))
            + " typ="
            + console_safe_text(str(record.get("type", "unbekannt"))),
        )


def run_chat(
    runtime: RuntimeClient,
    *,
    input_fn: Callable[[], str] = input,
    stdout: TextIO = sys.stdout,
    stderr: TextIO = sys.stderr,
) -> int:
    session = ChatSession(runtime)
    primary_error: ChatClientError | None = None
    interrupted = False
    try:
        session.open()
        write_line(stdout, "Kienzlefon-Chat (lokal, Kanal chat)")
        write_line(
            stdout,
            "Persistenter Modus: vollständige Aufträge werden wie Telefonanrufe gespeichert.",
        )
        write_line(stdout, "Hilfe mit /help; Beenden mit /quit oder Strg+D.")
        while True:
            write_prompt(stdout)
            try:
                text = input_fn()
            except EOFError:
                write_line(stdout)
                break
            except KeyboardInterrupt:
                write_line(stdout, "\nAbbruch angefordert.")
                interrupted = True
                break
            if not isinstance(text, str):
                raise ConfigurationError("Terminaleingabe ist kein Text")
            text = text.strip()
            if not text:
                continue
            if text == "/help":
                write_line(stdout, HELP_TEXT)
                continue
            if text == "/state":
                show_last_value(
                    stdout,
                    session.last_turn,
                    "state",
                    "Noch kein Dialogzustand vorhanden.",
                )
                continue
            if text == "/raw":
                show_last_value(
                    stdout,
                    session.last_turn,
                    "raw_response",
                    "Noch keine Rohantwort vorhanden.",
                )
                continue
            if text == "/records":
                write_record_summary(stdout, session.last_records)
                continue
            if text in {"/hangup", "/quit"}:
                break
            if text.startswith("/"):
                write_line(stderr, f"Unbekannter Befehl: {console_safe_text(text)}")
                continue
            if len(text) > MAX_TURN_CHARACTERS or "\x00" in text:
                write_line(
                    stderr,
                    f"Eingabe muss 1 bis {MAX_TURN_CHARACTERS} Zeichen lang sein.",
                )
                continue
            try:
                response = session.send(text)
            except ChatClientError as exc:
                primary_error = exc
                break
            write_line(stdout, "Kienzlefon> " + console_safe_text(response["reply"]))
            if response["terminal"]:
                write_line(stdout, "[Dialog beendet]")
                break
    except KeyboardInterrupt:
        write_line(stdout, "\nAbbruch angefordert.")
        interrupted = True
    finally:
        try:
            closed, records = session.close()
            if closed:
                write_line(stdout, "Sitzung abgeschlossen und gelöscht.")
                write_record_summary(stdout, records)
        except ChatClientError as exc:
            if primary_error is None:
                primary_error = exc
            else:
                write_line(stderr, f"Zusätzlicher Fehler beim Aufräumen: {exc}")
    if primary_error is not None:
        raise primary_error
    return 130 if interrupted else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Interaktiver lokaler Kommandozeilen-Client für den "
            "Kienzlefon-Chatkanal. Vollständige Aufträge werden über den "
            "produktiven Kienzlefon-Spoolpfad gespeichert; Dialoge selbst "
            "werden nicht protokolliert."
        )
    )
    parser.add_argument("--version", action="version", version=VERSION)
    parser.add_argument("--backend-url", default=DEFAULT_BACKEND_URL)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        backend_url = assert_loopback_base_url(args.backend_url)
        if args.timeout <= 0:
            raise ConfigurationError("--timeout muss positiv sein")
        return run_chat(RuntimeClient(backend_url, args.timeout))
    except ChatClientError as exc:
        print(f"FEHLER: {exc}", file=sys.stderr)
        return 2
    except BrokenPipeError:
        return 0
    except BaseException as exc:
        print(f"FEHLER: interner Fehler ({type(exc).__name__})", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
PY
  chmod 0755 "$temp"
  mv -f "$temp" "$target"
}

write_capacity_publisher() {
  local target="$1"
  install -d -m 0755 "$(dirname "$target")"
  local temp="${target}.tmp.$$"
  cat >"$temp" <<'PY'
#!/usr/bin/env python3
"""Fail-closed Kienzlefon AI capacity publisher v2.5.1."""

from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import os
import queue
import re
import socket
import socketserver
import threading
import time
import tomllib
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import urlsplit, urlunsplit

VERSION = "2.5.1"
PROTOCOL = "kienzlefon-ai-admission-v1"
CONTROL_PROTOCOL = "kienzlefon-ai-capacity-control-v1"
MAX_MESSAGE_BYTES = 65_536
IDENTIFIER = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")
RUNTIME_STATES = frozenset({"not_ready", "ready", "in_call", "draining", "disabled"})
HANDOFF_TARGETS = frozenset(
    {"classic", "practice_queue", "pharmacy_queue", "super_priority"}
)


class PublisherError(RuntimeError):
    pass


@dataclass(frozen=True)
class PublisherConfig:
    publisher_id: str
    listener_host: str
    listener_port: int
    slot_count: int
    snapshot_interval_ms: int
    lease_ttl_ms: int
    connect_timeout_ms: int
    control_socket: Path
    llm_health_url: str
    llm_slots_url: str
    asr_health_url: str
    piper_health_url: str
    qwen_health_url: str
    tts_backend: str
    asr_phone_capacity: int

    @property
    def slot_ids(self) -> tuple[str, ...]:
        return tuple(f"ai-slot-{index:02d}" for index in range(self.slot_count))


@dataclass
class RuntimeSlot:
    slot_id: str
    state: str = "not_ready"
    reason: str = "not_ready"
    lease_id: str | None = None
    lease_created_at: float = 0.0


@dataclass(frozen=True)
class ServiceCapacity:
    available: int
    reason: str


@dataclass
class NetworkRequest:
    message: dict[str, Any]
    done: threading.Event
    response: Mapping[str, Any] | None = None
    error: str = ""
    cancelled: bool = False


def _endpoint(url: str, path: str, websocket: bool = False) -> str:
    parsed = urlsplit(url)
    scheme = parsed.scheme
    if websocket:
        scheme = {"ws": "http", "wss": "https"}.get(scheme, scheme)
    if scheme not in {"http", "https"} or not parsed.hostname:
        raise PublisherError("invalid_service_url")
    return urlunsplit((scheme, parsed.netloc, path, "", ""))


def load_config(path: str | Path) -> PublisherConfig:
    source = Path(path).expanduser().resolve()
    with source.open("rb") as handle:
        raw = tomllib.load(handle)
    backend = _section(raw, "backend")
    services = _section(raw, "services")
    dialog = _section(raw, "dialog")
    admission = _section(raw, "admission")
    if admission.get("enabled") is not True:
        raise PublisherError("admission_disabled")
    result = PublisherConfig(
        publisher_id=str(admission["publisher_id"]),
        listener_host=str(admission["listener_host"]),
        listener_port=int(admission["listener_port"]),
        slot_count=int(backend["slot_count"]),
        snapshot_interval_ms=int(admission["snapshot_interval_ms"]),
        lease_ttl_ms=int(admission["lease_ttl_ms"]),
        connect_timeout_ms=int(admission["connect_timeout_ms"]),
        control_socket=Path(str(admission["control_socket"])),
        llm_health_url=_endpoint(str(services["llm_url"]), "/health"),
        llm_slots_url=_endpoint(str(services["llm_url"]), "/slots"),
        asr_health_url=_endpoint(str(services["asr_url"]), "/health", websocket=True),
        piper_health_url=_endpoint(str(services["piper_url"]), "/health"),
        qwen_health_url=_endpoint(str(services["qwen_url"]), "/v1/health"),
        tts_backend=str(dialog["tts_backend"]),
        asr_phone_capacity=int(admission["asr_phone_capacity"]),
    )
    if not IDENTIFIER.fullmatch(result.publisher_id):
        raise PublisherError("invalid_publisher_id")
    try:
        address = ipaddress.ip_address(result.listener_host)
    except ValueError as exc:
        raise PublisherError("listener_host_not_ip") from exc
    if address.is_unspecified or address.is_multicast:
        raise PublisherError("listener_host_not_unicast")
    if result.slot_count != 3:
        raise PublisherError("slot_count_not_three")
    if not 1 <= result.listener_port <= 65535:
        raise PublisherError("invalid_listener_port")
    if not 250 <= result.snapshot_interval_ms <= 5000:
        raise PublisherError("invalid_snapshot_interval")
    if not result.snapshot_interval_ms * 2 < result.lease_ttl_ms <= 30000:
        raise PublisherError("invalid_lease_ttl")
    if not 100 <= result.connect_timeout_ms <= 10000:
        raise PublisherError("invalid_connect_timeout")
    if not result.control_socket.is_absolute():
        raise PublisherError("invalid_control_socket")
    if not 1 <= result.asr_phone_capacity <= 3:
        raise PublisherError("invalid_asr_capacity")
    if result.tts_backend not in {"qwen", "piper"}:
        raise PublisherError("invalid_tts_backend")
    return result


class CapacityState:
    def __init__(self, config: PublisherConfig) -> None:
        self.config = config
        self.lock = threading.RLock()
        self.changed = threading.Event()
        self.slots = {slot_id: RuntimeSlot(slot_id) for slot_id in config.slot_ids}
        self.last_capacity = ServiceCapacity(0, "not_ready")
        self.listener_connected = False
        self.last_snapshot_accepted = False
        self.last_free_slots = 0
        self.network_requests: queue.Queue[NetworkRequest] = queue.Queue(maxsize=128)

    def set_listener(self, connected: bool, snapshot_accepted: bool = False) -> None:
        with self.lock:
            self.listener_connected = connected
            self.last_snapshot_accepted = snapshot_accepted if connected else False

    def set_runtime_state(self, slot_id: str, state: str, reason: str) -> dict[str, Any]:
        if slot_id not in self.slots:
            return _control_result(False, "unknown_slot")
        if state not in RUNTIME_STATES:
            return _control_result(False, "invalid_state")
        if not isinstance(reason, str) or len(reason) > 80:
            return _control_result(False, "invalid_reason")
        with self.lock:
            slot = self.slots[slot_id]
            slot.state = state
            slot.reason = reason or state
            if state != "ready":
                slot.lease_id = None
                slot.lease_created_at = 0.0
            self.changed.set()
        return _control_result(True, state=state, slot_id=slot_id)

    def claim_lease(self, slot_id: str, lease_id: str, request_id: str) -> dict[str, Any]:
        if not IDENTIFIER.fullmatch(request_id):
            return _control_result(False, "invalid_request_id")
        now = time.monotonic()
        with self.lock:
            slot = self.slots.get(slot_id)
            valid = bool(
                slot
                and slot.state == "ready"
                and slot.lease_id == lease_id
                and now - slot.lease_created_at < self.config.lease_ttl_ms / 1000.0
                and self.last_capacity.available > 0
                and self.listener_connected
                and self.last_snapshot_accepted
            )
            if not valid:
                return _control_result(False, "lease_not_valid")
            slot.state = "in_call"
            slot.reason = "in_call"
            slot.lease_id = None
            slot.lease_created_at = 0.0
            self.changed.set()
        return _control_result(True, slot_id=slot_id, request_id=request_id)

    def build_snapshot(self, capacity: ServiceCapacity) -> list[dict[str, Any]]:
        now = time.monotonic()
        available_budget = max(0, capacity.available)
        result: list[dict[str, Any]] = []
        with self.lock:
            self.last_capacity = capacity
            for slot in self.slots.values():
                if slot.state != "ready":
                    result.append({
                        "slot_id": slot.slot_id,
                        "state": "not_free",
                        "reason": _network_reason(slot.reason),
                    })
                    continue
                if available_budget <= 0:
                    slot.lease_id = None
                    slot.lease_created_at = 0.0
                    result.append({
                        "slot_id": slot.slot_id,
                        "state": "not_free",
                        "reason": capacity.reason,
                    })
                    continue
                if (
                    slot.lease_id is None
                    or now - slot.lease_created_at >= self.config.lease_ttl_ms / 1000.0
                ):
                    slot.lease_id = str(uuid.uuid4())
                    slot.lease_created_at = now
                result.append({
                    "slot_id": slot.slot_id,
                    "state": "free",
                    "lease_id": slot.lease_id,
                    "ttl_ms": self.config.lease_ttl_ms,
                })
                available_budget -= 1
            self.last_free_slots = sum(item["state"] == "free" for item in result)
        return result

    def status(self) -> dict[str, Any]:
        with self.lock:
            slots = {
                slot_id: {"state": slot.state, "reason": slot.reason}
                for slot_id, slot in self.slots.items()
            }
            return {
                "protocol": CONTROL_PROTOCOL,
                "command": "status_result",
                "accepted": True,
                "listener_connected": self.listener_connected,
                "last_snapshot_accepted": self.last_snapshot_accepted,
                "free_slots": self.last_free_slots,
                "service_capacity": self.last_capacity.available,
                "service_reason": self.last_capacity.reason,
                "slots": slots,
            }

    def network_command(self, message: Mapping[str, Any]) -> dict[str, Any]:
        command = message.get("command")
        if command == "get_call_policy":
            if set(message) != {"protocol", "command", "request_id", "lease_id"}:
                return _control_result(False, "invalid_network_request")
            if not all(
                IDENTIFIER.fullmatch(str(message.get(name, "")))
                for name in ("request_id", "lease_id")
            ):
                return _control_result(False, "invalid_network_request")
        elif command == "publish_call_result":
            if set(message) != {"protocol", "command", "result"}:
                return _control_result(False, "invalid_network_request")
            result = message.get("result")
            if not isinstance(result, Mapping) or set(result) != {
                "protocol", "request_id", "lease_id", "outcome",
                "handoff_target", "commit_status",
            }:
                return _control_result(False, "invalid_network_request")
            if (
                result.get("protocol") != "kienzlefon-ai-call-result-v1"
                or result.get("outcome") != "handoff_requested"
                or result.get("handoff_target") not in HANDOFF_TARGETS
                or result.get("commit_status") != "not_committed"
                or not all(
                    IDENTIFIER.fullmatch(str(result.get(name, "")))
                    for name in ("request_id", "lease_id")
                )
            ):
                return _control_result(False, "invalid_network_request")
        else:
            return _control_result(False, "invalid_network_request")
        network_message = dict(message)
        network_message["protocol"] = PROTOCOL
        request = NetworkRequest(network_message, threading.Event())
        try:
            self.network_requests.put_nowait(request)
        except queue.Full:
            return _control_result(False, "network_request_queue_full")
        self.changed.set()
        if not request.done.wait(15.0):
            request.cancelled = True
            return _control_result(False, "network_request_timeout")
        if request.response is None:
            return _control_result(False, request.error or "network_request_failed")
        return _control_result(True, response=dict(request.response))

    def fail_network_requests(self, reason: str) -> None:
        while True:
            try:
                request = self.network_requests.get_nowait()
            except queue.Empty:
                return
            request.error = reason
            request.done.set()


class ServiceProbe:
    def __init__(self, config: PublisherConfig) -> None:
        self.config = config

    def capacity(self) -> ServiceCapacity:
        try:
            llm_health = _get_json(self.config.llm_health_url)
            llm_slots = _get_json(self.config.llm_slots_url)
            asr_health = _get_json(self.config.asr_health_url)
            piper_health = _get_json(self.config.piper_health_url)
            if self.config.tts_backend == "qwen":
                try:
                    _get_json(self.config.qwen_health_url)
                except Exception:
                    pass  # Piper is the guaranteed, independently probed fallback.
            if not _healthy(llm_health) or not _healthy(asr_health) or not _healthy(piper_health):
                return ServiceCapacity(0, "service_unavailable")
            if not isinstance(llm_slots, list):
                return ServiceCapacity(0, "service_unavailable")
            llm_free = sum(
                1
                for slot in llm_slots
                if isinstance(slot, Mapping) and slot.get("is_processing") is False
            )
            tts_free = piper_health.get("workers_available", 0)
            if isinstance(tts_free, bool) or not isinstance(tts_free, int):
                return ServiceCapacity(0, "service_unavailable")
            available = min(
                llm_free,
                max(0, tts_free),
                self.config.asr_phone_capacity,
                self.config.slot_count,
            )
            return ServiceCapacity(available, "no_capacity" if available == 0 else "")
        except Exception:
            return ServiceCapacity(0, "service_unavailable")


class ControlHandler(socketserver.StreamRequestHandler):
    server: "ControlServer"

    def handle(self) -> None:
        raw = self.rfile.readline(MAX_MESSAGE_BYTES + 1)
        if not raw or len(raw) > MAX_MESSAGE_BYTES or not raw.endswith(b"\n"):
            return
        try:
            message = json.loads(raw)
            if not isinstance(message, Mapping) or message.get("protocol") != CONTROL_PROTOCOL:
                raise ValueError("invalid_protocol")
            command = message.get("command")
            if command == "set_slot_state":
                response = self.server.state.set_runtime_state(
                    str(message.get("slot_id", "")),
                    str(message.get("state", "")),
                    str(message.get("reason", "")),
                )
            elif command == "claim_lease":
                response = self.server.state.claim_lease(
                    str(message.get("slot_id", "")),
                    str(message.get("lease_id", "")),
                    str(message.get("request_id", "")),
                )
            elif command == "status":
                response = self.server.state.status()
            elif command in {"get_call_policy", "publish_call_result"}:
                response = self.server.state.network_command(message)
            else:
                response = _control_result(False, "unknown_command")
        except Exception:
            response = _control_result(False, "invalid_message")
        self.wfile.write(json.dumps(response, separators=(",", ":")).encode() + b"\n")


class ControlServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True

    def __init__(self, path: str, state: CapacityState) -> None:
        self.state = state
        super().__init__(path, ControlHandler)


class CapacityPublisher:
    def __init__(self, config: PublisherConfig, state: CapacityState, probe: ServiceProbe) -> None:
        self.config = config
        self.state = state
        self.probe = probe
        self.sequence = 0

    def run_forever(self) -> None:
        while True:
            try:
                self._connected_loop()
            except Exception as error:
                self.state.set_listener(False)
                self.state.fail_network_requests("listener_unavailable")
                logging.warning("event=listener_unavailable code=%s", type(error).__name__)
                time.sleep(1.0)

    def _connected_loop(self) -> None:
        timeout = self.config.connect_timeout_ms / 1000.0
        with socket.create_connection(
            (self.config.listener_host, self.config.listener_port), timeout=timeout
        ) as connection:
            connection.settimeout(max(timeout, self.config.snapshot_interval_ms / 1000.0 + 1.0))
            reader = connection.makefile("rb")
            response = _exchange(connection, reader, {
                "protocol": PROTOCOL,
                "command": "publisher_hello",
                "publisher_id": self.config.publisher_id,
                "slot_count": self.config.slot_count,
            })
            if (
                response.get("command") != "publisher_hello_result"
                or response.get("accepted") is not True
                or response.get("configured_slot_count") != self.config.slot_count
                or response.get("slot_ids") != list(self.config.slot_ids)
                or response.get("lease_ttl_ms") != self.config.lease_ttl_ms
                or not isinstance(response.get("publisher_timeout_ms"), int)
                or response["publisher_timeout_ms"] < self.config.lease_ttl_ms
            ):
                raise PublisherError("publisher_hello_rejected")
            self.state.set_listener(True)
            logging.info("event=listener_connected")
            while True:
                capacity = self.probe.capacity()
                # Serialize the accepted network snapshot with local lease claims.
                # Otherwise a pre-built free snapshot could race a consumed lease.
                with self.state.lock:
                    slots = self.state.build_snapshot(capacity)
                    self.sequence += 1
                    response = _exchange(connection, reader, {
                        "protocol": PROTOCOL,
                        "command": "capacity_snapshot",
                        "sequence": self.sequence,
                        "slots": slots,
                    })
                    if (
                        response.get("command") != "capacity_snapshot_result"
                        or response.get("accepted") is not True
                        or response.get("sequence") != self.sequence
                        or isinstance(response.get("free_slots"), bool)
                        or not isinstance(response.get("free_slots"), int)
                        or not 0 <= response["free_slots"] <= self.config.slot_count
                    ):
                        raise PublisherError("capacity_snapshot_rejected")
                    self.state.set_listener(True, True)
                while True:
                    try:
                        request = self.state.network_requests.get_nowait()
                    except queue.Empty:
                        break
                    if request.cancelled:
                        continue
                    try:
                        request.response = _exchange(
                            connection, reader, request.message
                        )
                    except Exception:
                        request.error = "listener_exchange_failed"
                        request.done.set()
                        raise
                    request.done.set()
                self.state.changed.wait(self.config.snapshot_interval_ms / 1000.0)
                self.state.changed.clear()


def run_control_server(config: PublisherConfig, state: CapacityState) -> ControlServer:
    config.control_socket.parent.mkdir(parents=True, exist_ok=True)
    config.control_socket.unlink(missing_ok=True)
    server = ControlServer(str(config.control_socket), state)
    os.chmod(config.control_socket, 0o660)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def self_test() -> int:
    config = PublisherConfig(
        publisher_id="self-test", listener_host="127.0.0.1", listener_port=8190,
        slot_count=3, snapshot_interval_ms=1000, lease_ttl_ms=5000,
        connect_timeout_ms=1000, control_socket=Path("/tmp/self-test.sock"),
        llm_health_url="http://127.0.0.1/health",
        llm_slots_url="http://127.0.0.1/slots",
        asr_health_url="http://127.0.0.1/health",
        piper_health_url="http://127.0.0.1/health",
        qwen_health_url="http://127.0.0.1/v1/health",
        tts_backend="qwen", asr_phone_capacity=3,
    )
    state = CapacityState(config)
    initial = state.build_snapshot(ServiceCapacity(3, ""))
    assert all(item["state"] == "not_free" for item in initial)
    for slot_id in config.slot_ids:
        assert state.set_runtime_state(slot_id, "ready", "ready")["accepted"]
    snapshot = state.build_snapshot(ServiceCapacity(3, ""))
    assert len(snapshot) == 3 and all(item["state"] == "free" for item in snapshot)
    leases = {item["lease_id"] for item in snapshot}
    assert len(leases) == 3
    first = snapshot[0]
    disconnected = state.claim_lease(first["slot_id"], first["lease_id"], "request-00")
    assert disconnected["accepted"] is False
    state.set_listener(True, True)
    accepted = state.claim_lease(first["slot_id"], first["lease_id"], "request-01")
    assert accepted["accepted"] is True
    replay = state.claim_lease(first["slot_id"], first["lease_id"], "request-02")
    assert replay["accepted"] is False
    second = snapshot[1]
    state.slots[second["slot_id"]].lease_created_at -= 6.0
    expired = state.claim_lease(second["slot_id"], second["lease_id"], "request-03")
    assert expired["accepted"] is False
    assert state.set_runtime_state(first["slot_id"], "draining", "draining")["accepted"]
    assert state.set_runtime_state(first["slot_id"], "ready", "ready")["accepted"]
    assert state.claim_lease("missing", str(uuid.uuid4()), "request-04")["accepted"] is False
    forwarded: list[dict[str, Any]] = []

    def request_policy() -> None:
        forwarded.append(state.network_command({
            "protocol": CONTROL_PROTOCOL,
            "command": "get_call_policy",
            "request_id": "request-05",
            "lease_id": str(uuid.uuid4()),
        }))

    thread = threading.Thread(target=request_policy)
    thread.start()
    network_request = state.network_requests.get(timeout=1.0)
    assert network_request.message["protocol"] == PROTOCOL
    network_request.response = {
        "protocol": PROTOCOL,
        "command": "get_call_policy_result",
        "accepted": False,
        "reason": "claim_not_found",
    }
    network_request.done.set()
    thread.join(timeout=1.0)
    assert forwarded and forwarded[0]["accepted"] is True
    invalid_result = state.network_command({
        "protocol": CONTROL_PROTOCOL,
        "command": "publish_call_result",
        "result": {"protocol": "wrong"},
    })
    assert invalid_result["accepted"] is False
    print("capacity publisher self-test: ok")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Kienzlefon AI capacity publisher")
    parser.add_argument("--config", default="/etc/kienzlefon-ai-asterisk-backend/backend.toml")
    parser.add_argument("--check-config", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    args = parser.parse_args()
    if args.self_test:
        raise SystemExit(self_test())
    config = load_config(args.config)
    if args.check_config:
        print("configuration valid")
        return
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    state = CapacityState(config)
    control = run_control_server(config, state)
    try:
        CapacityPublisher(config, state, ServiceProbe(config)).run_forever()
    finally:
        control.shutdown()
        control.server_close()
        config.control_socket.unlink(missing_ok=True)


def _section(raw: Mapping[str, Any], name: str) -> Mapping[str, Any]:
    value = raw.get(name)
    if not isinstance(value, Mapping):
        raise PublisherError(f"missing_section_{name}")
    return value


def _healthy(value: Any) -> bool:
    return isinstance(value, Mapping) and value.get("status") in {"ok", "healthy"}


def _get_json(url: str) -> Any:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=1.0) as response:
        if not 200 <= response.status < 300:
            raise PublisherError("health_http_failure")
        return json.load(response)


def _exchange(connection: socket.socket, reader: Any, message: Mapping[str, Any]) -> dict[str, Any]:
    connection.sendall(json.dumps(message, separators=(",", ":")).encode() + b"\n")
    raw = reader.readline(MAX_MESSAGE_BYTES + 1)
    if not raw or len(raw) > MAX_MESSAGE_BYTES or not raw.endswith(b"\n"):
        raise PublisherError("listener_response_invalid")
    response = json.loads(raw)
    if not isinstance(response, dict) or response.get("protocol") != PROTOCOL:
        raise PublisherError("listener_protocol_invalid")
    return response


def _control_result(accepted: bool, reason: str = "", **values: Any) -> dict[str, Any]:
    return {
        "protocol": CONTROL_PROTOCOL,
        "command": "control_result",
        "accepted": accepted,
        **({} if accepted or not reason else {"reason": reason}),
        **values,
    }


def _network_reason(reason: str) -> str:
    allowed = {
        "in_call", "draining", "no_capacity", "not_ready", "maintenance",
        "service_unavailable", "slot_disabled",
    }
    return reason if reason in allowed else "not_ready"


if __name__ == "__main__":
    main()
PY
  chmod 0755 "$temp"
  mv -f "$temp" "$target"
}

get_kienzlefon_paths() {
  local path
  local -a paths=()
  [[ -x "$KIENZLEFON_PYTHON" ]] || die "Kienzlefon Python environment is missing: $KIENZLEFON_PYTHON"
  [[ -r "$KIENZLEFON_CONFIG" ]] || die "Kienzlefon configuration is missing: $KIENZLEFON_CONFIG"
  mapfile -t paths < <("$KIENZLEFON_PYTHON" - "$KIENZLEFON_CONFIG" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as handle:
    data = tomllib.load(handle)
print(data["pfade"]["spool"])
print(data["telepraxis"]["ausgabeverzeichnis"])
PY
  )
  [[ ${#paths[@]} -eq 2 && "${paths[0]}" == /* && "${paths[1]}" == /* ]] \
    || die "Kienzlefon spool/output paths are invalid."
  for path in "${paths[@]}"; do
    [[ "$path" =~ ^/[A-Za-z0-9._/-]+$ ]] \
      || die "Kienzlefon paths must use systemd-safe absolute characters: $path"
  done
  printf '%s\n%s\n' "${paths[0]}" "${paths[1]}"
}

render_tree() {
  local root="$1" spool_path="${2:-/var/spool/kienzlefon}" output_path="${3:-/srv/telepraxis/test/inbox}"
  local asterisk_group="${4:-root}"
  [[ -n "$root" && "$root" == /* ]] || die "Render target must be an absolute path."
  if [[ -e "$root" ]]; then
    [[ -d "$root" ]] || die "Render target exists and is not a directory."
    [[ -z "$(find "$root" -mindepth 1 -maxdepth 1 -print -quit)" ]] \
      || die "Render target must be empty."
  else
    install -d -m 0750 "$root"
  fi
  write_backend_config "$root$CONFIG_FILE"
  write_agent "$root$AGENT_PATH"
  write_tts_guard "$root$TTS_GUARD_PATH"
  write_chat_client "$root$CHAT_CLIENT_PATH"
  write_capacity_publisher "$root$CAPACITY_PATH"
  write_reload_command "$root$RELOAD_PATH"
  write_debug_console "$root$DEBUG_CONSOLE_PATH"
  write_performance_report "$root$PERFORMANCE_REPORT_PATH"
  write_pjsip_config "$root$ASTERISK_ETC/pjsip.conf"
  write_extensions_config "$root$ASTERISK_ETC/extensions.conf"
  write_systemd_unit "$root$UNIT_FILE" "$spool_path" "$output_path" "$asterisk_group"
  write_capacity_systemd_unit "$root$CAPACITY_UNIT_FILE" "$asterisk_group"
  write_text_systemd_unit "$root$TEXT_UNIT_FILE" "$spool_path" "$output_path"
}

detect_asterisk_identity() {
  ASTERISK_RUNTIME_USER="$(
    ps -eo user=,comm= | awk '$2 == "asterisk" { print $1; exit }'
  )"
  ASTERISK_RUNTIME_USER="${ASTERISK_RUNTIME_USER:-root}"
  getent passwd "$ASTERISK_RUNTIME_USER" >/dev/null \
    || die "Asterisk runtime user does not exist: $ASTERISK_RUNTIME_USER"
  ASTERISK_RUNTIME_GROUP="$(id -gn "$ASTERISK_RUNTIME_USER")"
  [[ "$ASTERISK_RUNTIME_GROUP" =~ ^[A-Za-z0-9_.-]+$ ]] \
    || die "Asterisk runtime group is invalid: $ASTERISK_RUNTIME_GROUP"
}

verify_kienzlefon_commit_api() {
  "$KIENZLEFON_PYTHON" - <<'PY'
from kienzlefon.models import AudioStatus, CallState, CallType, FieldName
from kienzlefon.spool import SUMMARY_UNAVAILABLE, Spool, WorkingCall
from kienzlefon.worker import Worker

required_call_types = {
    "rezeptbestellung",
    "ueb_req",
    "termin",
    "rueckruf_details",
    "rueckruf_tel_grund",
    "sonstiges",
}
if not required_call_types.issubset({value.value for value in CallType}):
    raise SystemExit("required Kienzlefon call types are missing")
if AudioStatus.TRANSCRIBED.value != "transcribed":
    raise SystemExit("Kienzlefon transcribed state is incompatible")
if FieldName.MEDICATION.value != "medikamente":
    raise SystemExit("Kienzlefon medication field is incompatible")
if CallState.PROCESSING.value != "processing" or CallState.READY.value != "ready":
    raise SystemExit("Kienzlefon spool states are incompatible")
if not isinstance(SUMMARY_UNAVAILABLE, str) or not SUMMARY_UNAVAILABLE:
    raise SystemExit("Kienzlefon summary placeholder is incompatible")
for owner, method in ((Spool, "create_call"), (Spool, "transition"), (WorkingCall, "save"), (Worker, "process")):
    if not callable(getattr(owner, method, None)):
        raise SystemExit(f"Kienzlefon API is missing {owner.__name__}.{method}")
PY
}

asterisk_wideband_failure() {
  printf 'Asterisk G.722/AudioSocket wideband capability failed: %s\n' "$1" >&2
  return 1
}

asterisk_call_primitive_failure() {
  printf 'Asterisk call primitive capability failed: %s\n' "$1" >&2
  return 1
}

verify_asterisk_call_primitives() {
  local dial_application uuid_function
  # Capture the complete CLI response before searching it.  With pipefail,
  # `asterisk ... | grep -q` can otherwise report status 141 when grep exits
  # after its first match in the long Dial application documentation.
  dial_application="$(asterisk -rx 'core show application Dial' 2>/dev/null)" \
    || { asterisk_call_primitive_failure "app_dial cannot be queried"; return 1; }
  grep -q 'Dial' <<<"$dial_application" \
    || { asterisk_call_primitive_failure "app_dial is not available"; return 1; }

  uuid_function="$(asterisk -rx 'core show function UUID' 2>/dev/null)" \
    || { asterisk_call_primitive_failure "func_uuid cannot be queried"; return 1; }
  grep -q 'UUID' <<<"$uuid_function" \
    || { asterisk_call_primitive_failure "func_uuid is not available"; return 1; }
}

verify_asterisk_wideband() {
  local modules g722_module codecs slin_paths g722_paths settings
  local module_directory module_path symbols
  modules="$(asterisk -rx 'module show like audiosocket' 2>/dev/null)" \
    || { asterisk_wideband_failure "AudioSocket modules cannot be queried"; return 1; }
  grep -q 'chan_audiosocket\.so' <<<"$modules" \
    || { asterisk_wideband_failure "chan_audiosocket is not loaded"; return 1; }
  grep -q 'res_audiosocket\.so' <<<"$modules" \
    || { asterisk_wideband_failure "res_audiosocket is not loaded"; return 1; }
  g722_module="$(asterisk -rx 'module show like codec_g722' 2>/dev/null)" \
    || { asterisk_wideband_failure "codec_g722 module cannot be queried"; return 1; }
  grep -q 'codec_g722\.so' <<<"$g722_module" \
    || { asterisk_wideband_failure "codec_g722 is not loaded"; return 1; }

  codecs="$(asterisk -rx 'core show codecs audio' 2>/dev/null)" \
    || { asterisk_wideband_failure "audio codecs cannot be queried"; return 1; }
  grep -Eq '[[:space:]]slin16[[:space:]]' <<<"$codecs" \
    || { asterisk_wideband_failure "slin16 is unavailable"; return 1; }
  grep -Eq '[[:space:]]g722[[:space:]]' <<<"$codecs" \
    || { asterisk_wideband_failure "g722 is unavailable"; return 1; }

  slin_paths="$(asterisk -rx 'core show translation paths slin 16000' 2>/dev/null)" \
    || { asterisk_wideband_failure "slin 16000 translation paths cannot be queried"; return 1; }
  grep -q 'g722:16000' <<<"$slin_paths" \
    || { asterisk_wideband_failure "slin16 to G.722 translation path is missing"; return 1; }
  g722_paths="$(asterisk -rx 'core show translation paths g722 16000' 2>/dev/null)" \
    || { asterisk_wideband_failure "G.722 translation paths cannot be queried"; return 1; }
  grep -q 'slin:16000' <<<"$g722_paths" \
    || { asterisk_wideband_failure "G.722 to slin16 translation path is missing"; return 1; }

  # Asterisk 20.6 already knows the slin16 core format and the channel option,
  # but its res_audiosocket still serializes every frame as 0x10/8 kHz.  Test
  # the installed module capability instead of parsing release or Git strings.
  settings="$(asterisk -rx 'core show settings' 2>/dev/null)" \
    || { asterisk_wideband_failure "Asterisk module directory cannot be queried"; return 1; }
  module_directory="$(awk '
    tolower($0) ~ /^[[:space:]]*module directory:/ {
      sub(/^[^:]*:[[:space:]]*/, ""); print; exit
    }
  ' <<<"$settings")"
  [[ -n "$module_directory" && "$module_directory" == /* ]] \
    || { asterisk_wideband_failure "Asterisk module directory is invalid"; return 1; }
  module_path="${module_directory%/}/res_audiosocket.so"
  [[ -r "$module_path" ]] \
    || { asterisk_wideband_failure "res_audiosocket module file is unreadable"; return 1; }
  symbols="$(nm -D -- "$module_path" 2>/dev/null)" \
    || { asterisk_wideband_failure "res_audiosocket symbols cannot be inspected"; return 1; }
  grep -Eq '[[:space:]]ast_format_slin16$' <<<"$symbols" \
    || { asterisk_wideband_failure "res_audiosocket lacks multi-rate slin16 support"; return 1; }
}

resolve_existing_path() {
  local path="$1" resolver_python="${2:-/usr/bin/python3}"
  if [[ ! -x "$resolver_python" ]]; then
    resolver_python="$(command -v python3 || true)"
  fi
  [[ -n "$resolver_python" && -x "$resolver_python" ]] || return 1
  "$resolver_python" - "$path" <<'PY'
import sys
from pathlib import Path

try:
    resolved = Path(sys.argv[1]).resolve(strict=True)
except (OSError, RuntimeError):
    raise SystemExit(1)
print(resolved)
PY
}

chat_target_is_managed() {
  local resolved_target="$1"
  local current_target="${2:-$CHAT_CLIENT_PATH}"
  local legacy_directory="${3:-/usr/local/lib/kienzlefon-chat}"
  local target_directory target_name
  [[ "$resolved_target" == "$current_target" ]] && return 0
  target_directory="$(dirname -- "$resolved_target")"
  target_name="$(basename -- "$resolved_target")"
  [[ "$target_directory" == "$legacy_directory" ]] || return 1
  [[ "$target_name" == kienzlefon-chat-client-v*.py ]]
}

validate_chat_command_path() {
  local raw_target="" resolved_target=""
  if [[ ! -e "$CHAT_COMMAND_PATH" && ! -L "$CHAT_COMMAND_PATH" ]]; then
    return 0
  fi
  [[ -L "$CHAT_COMMAND_PATH" ]] \
    || die "Existing chat command is not a symbolic link: $CHAT_COMMAND_PATH"
  raw_target="$(readlink -- "$CHAT_COMMAND_PATH")"
  resolved_target="$(resolve_existing_path "$CHAT_COMMAND_PATH")" \
    || die "Existing chat command target cannot be resolved: $raw_target"
  [[ -f "$resolved_target" ]] \
    || die "Existing chat command target is not a regular file: $raw_target"
  chat_target_is_managed "$resolved_target" \
    || die "Existing chat command points to an unmanaged target: $raw_target (resolved: $resolved_target)"
}

install_chat_command() {
  validate_chat_command_path
  ln -sfn -- "$CHAT_CLIENT_PATH" "$CHAT_COMMAND_PATH"
}

preflight_install() {
  local command
  local -a kpaths=()
  [[ -r /etc/os-release ]] || die "This installer requires Ubuntu Linux."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Only Ubuntu is supported by version 2.5.1."
  for command in \
    asterisk systemctl ip install cp mv find ps awk getent id chown grep date chmod \
    basename dirname mktemp readlink sleep rm nm; do
    command -v "$command" >/dev/null || die "Required command is missing: $command"
  done
  /usr/bin/python3 -c 'import asyncio,http.client,tomllib' \
    || die "Python 3.11+ is required."
  [[ -d "$ASTERISK_ETC" ]] || die "Asterisk configuration directory is missing."
  [[ -r "$ASTERISK_ETC/pjsip.conf" && -r "$ASTERISK_ETC/extensions.conf" ]] \
    || die "Fresh Kienzlefon Asterisk configuration is incomplete."
  mapfile -t kpaths < <(get_kienzlefon_paths)
  [[ -d "${kpaths[0]}" && -d "${kpaths[1]}" ]] \
    || die "Kienzlefon spool or output directory does not exist."
  verify_kienzlefon_commit_api \
    || die "Installed Kienzlefon commit API is incompatible with backend v2.5.1."
  EXPECTED_BIND_IP="$BACKEND_BIND_IP" verify_local_bind_ip
  verify_asterisk_call_primitives \
    || die "Asterisk does not provide the required Dial and UUID primitives."
  verify_asterisk_wideband \
    || die "Asterisk does not provide the required G.722/slin16 AudioSocket path."
  detect_asterisk_identity
  validate_chat_command_path
}

backup_asterisk() {
  local stamp name
  stamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="${BACKUP_ROOT}/${stamp}"
  [[ ! -e "$BACKUP_DIR" ]] || BACKUP_DIR="${BACKUP_DIR}-$$"
  install -d -m 0700 "$BACKUP_DIR/asterisk" "$BACKUP_DIR/backend"
  cp -a "$ASTERISK_ETC/." "$BACKUP_DIR/asterisk/"
  backup_optional_file "$CONFIG_FILE" config
  backup_optional_file "$AGENT_PATH" agent
  backup_optional_file "$TTS_GUARD_PATH" tts-guard
  backup_optional_file "$CHAT_CLIENT_PATH" chat-client
  backup_optional_file "$CHAT_COMMAND_PATH" chat-command
  backup_optional_file "$UNIT_FILE" unit
  backup_optional_file "$CAPACITY_PATH" capacity
  backup_optional_file "$CAPACITY_UNIT_FILE" capacity-unit
  backup_optional_file "$TEXT_UNIT_FILE" text-unit
  backup_optional_file "$RELOAD_PATH" reload-command
  backup_optional_file "$STATE_DIR/last-reload.toml" last-reload-config
  backup_optional_file "$DEBUG_CONSOLE_PATH" debug-console
  backup_optional_file "$PERFORMANCE_REPORT_PATH" performance-report
  for name in 01-bitte-warten.pcm 02-ich-verarbeite.pcm 03-bitte-warten.pcm manifest.json; do
    backup_optional_file "$FILLER_DIR/$name" "filler-$name"
  done
  printf '%s\n' "$BACKUP_DIR" >"${STATE_DIR}/last-backup"
  chmod 0600 "${STATE_DIR}/last-backup"
  log "Asterisk and backend backup created at ${BACKUP_DIR}."
}

backup_optional_file() {
  local source="$1" name="$2"
  if [[ -e "$source" || -L "$source" ]]; then
    cp -a "$source" "$BACKUP_DIR/backend/$name"
    printf 'present\n' >"$BACKUP_DIR/backend/${name}.state"
  else
    printf 'absent\n' >"$BACKUP_DIR/backend/${name}.state"
  fi
}

restore_optional_file() {
  local target="$1" name="$2" state_file
  state_file="$BACKUP_DIR/backend/${name}.state"
  [[ -r "$state_file" ]] || return 1
  if [[ "$(<"$state_file")" == "present" ]]; then
    cp -a "$BACKUP_DIR/backend/$name" "$target"
  else
    rm -f -- "$target"
  fi
}

capture_service_state() {
  local unit="$1" prefix="$2" exists="n" enabled="n" active="n"
  if systemctl cat "$unit" >/dev/null 2>&1; then
    exists="y"
    systemctl is-enabled --quiet "$unit" 2>/dev/null && enabled="y"
    systemctl is-active --quiet "$unit" 2>/dev/null && active="y"
  fi
  printf -v "${prefix}_EXISTS" '%s' "$exists"
  printf -v "${prefix}_WAS_ENABLED" '%s' "$enabled"
  printf -v "${prefix}_WAS_ACTIVE" '%s' "$active"
}

capture_service_states() {
  local index
  capture_service_state kienzlefon-worker.service OLD_WORKER
  capture_service_state kienzlefon-admission-listener.service OLD_LISTENER
  capture_service_state kienzlefon-ai-capacity-publisher.service OLD_CAPACITY
  capture_service_state kienzlefon-ai-text.service OLD_TEXT
  for index in 0 1 2; do
    capture_service_state "kienzlefon-ai-agent@${index}.service" "OLD_AGENT_${index}"
  done
}

restore_service_state() {
  local unit="$1" prefix="$2"
  local exists_name="${prefix}_EXISTS"
  local enabled_name="${prefix}_WAS_ENABLED"
  local active_name="${prefix}_WAS_ACTIVE"
  if [[ "${!exists_name:-n}" != "y" ]]; then
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
    return
  fi
  if [[ "${!enabled_name:-n}" == "y" ]]; then
    systemctl enable "$unit" >/dev/null 2>&1 || true
  else
    systemctl disable "$unit" >/dev/null 2>&1 || true
  fi
  if [[ "${!active_name:-n}" == "y" ]]; then
    systemctl start "$unit" >/dev/null 2>&1 || true
  else
    systemctl stop "$unit" >/dev/null 2>&1 || true
  fi
}

rollback_install() {
  local index name
  [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || return 0
  log "Restoring Asterisk, backend files and service states from ${BACKUP_DIR}."
  systemctl disable --now kienzlefon-ai-capacity-publisher.service >/dev/null 2>&1 || true
  systemctl disable --now kienzlefon-ai-text.service >/dev/null 2>&1 || true
  for index in 0 1 2; do
    systemctl disable --now "kienzlefon-ai-agent@${index}.service" >/dev/null 2>&1 || true
  done
  cp -a "$BACKUP_DIR/asterisk/." "$ASTERISK_ETC/"
  restore_optional_file "$CONFIG_FILE" config || true
  restore_optional_file "$AGENT_PATH" agent || true
  restore_optional_file "$TTS_GUARD_PATH" tts-guard || true
  restore_optional_file "$CHAT_CLIENT_PATH" chat-client || true
  restore_optional_file "$CHAT_COMMAND_PATH" chat-command || true
  restore_optional_file "$UNIT_FILE" unit || true
  restore_optional_file "$CAPACITY_PATH" capacity || true
  restore_optional_file "$CAPACITY_UNIT_FILE" capacity-unit || true
  restore_optional_file "$TEXT_UNIT_FILE" text-unit || true
  restore_optional_file "$RELOAD_PATH" reload-command || true
  restore_optional_file "$STATE_DIR/last-reload.toml" last-reload-config || true
  restore_optional_file "$DEBUG_CONSOLE_PATH" debug-console || true
  restore_optional_file "$PERFORMANCE_REPORT_PATH" performance-report || true
  for name in 01-bitte-warten.pcm 02-ich-verarbeite.pcm 03-bitte-warten.pcm manifest.json; do
    restore_optional_file "$FILLER_DIR/$name" "filler-$name" || true
  done
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart asterisk.service >/dev/null 2>&1 || true
  restore_service_state kienzlefon-worker.service OLD_WORKER
  restore_service_state kienzlefon-admission-listener.service OLD_LISTENER
  restore_service_state kienzlefon-ai-capacity-publisher.service OLD_CAPACITY
  restore_service_state kienzlefon-ai-text.service OLD_TEXT
  for index in 0 1 2; do
    restore_service_state "kienzlefon-ai-agent@${index}.service" "OLD_AGENT_${index}"
  done
}

on_install_error() {
  local status=$? line="${BASH_LINENO[0]:-unknown}"
  trap - ERR
  set +e
  if [[ "$INSTALL_STARTED" == "y" ]]; then
    printf 'ERROR: Installation failed near line %s; attempting complete rollback.\n' "$line" >&2
    rollback_install
  fi
  exit "$status"
}

install_backend() {
  local confirmation="" spool_path output_path stage index name
  local -a kpaths=()
  require_root
  load_existing_config
  load_system_prompt_file
  collect_configuration
  validate_configuration
  preflight_install
  [[ ! -L "$INSTALL_ROOT/audio" && ! -L "$FILLER_DIR" ]] || die "Managed filler directory must not be a symlink."
  for name in 01-bitte-warten.pcm 02-ich-verarbeite.pcm 03-bitte-warten.pcm manifest.json; do
    [[ ! -L "$FILLER_DIR/$name" && ( ! -e "$FILLER_DIR/$name" || -f "$FILLER_DIR/$name" ) ]] \
      || die "Managed filler files must be regular files, not symlinks."
  done
  if [[ "$NON_INTERACTIVE" != "y" ]]; then
    printf '\nWARNING: This replaces pjsip.conf and extensions.conf on this dedicated backend.\n'
    printf '2.5.1 switches to block ASR and disables speculation. Do not update during active calls.\n'
    printf 'Static filler clips are prepared once via the existing Qwen service (no model/service changes).\n'
    ask_yes_no confirmation "Continue after creating a complete backup?" "n"
    [[ "$confirmation" == "y" ]] || die "Installation cancelled."
  fi

  mapfile -t kpaths < <(get_kienzlefon_paths)
  spool_path="${kpaths[0]}"
  output_path="${kpaths[1]}"
  install -d -m 0750 "$INSTALL_ROOT/bin" "$CONFIG_DIR" "$STATE_DIR" "$STATE_DIR/commits" "$BACKUP_ROOT" "$PERFORMANCE_LOG_DIR"
  install -d -m 0755 "$(dirname "$RELOAD_PATH")"
  stage="$(mktemp -d /tmp/kienzlefon-ai-backend-stage.XXXXXX)"
  TEMP_DIRS+=("$stage")
  MAIN_HOST="$MAIN_HOST" BACKEND_BIND_IP="$BACKEND_BIND_IP" \
    render_tree "$stage" "$spool_path" "$output_path" "$ASTERISK_RUNTIME_GROUP"
  PYTHONPYCACHEPREFIX="$stage/pycache" /usr/bin/python3 -m py_compile "$stage$AGENT_PATH"
  PYTHONPYCACHEPREFIX="$stage/pycache" /usr/bin/python3 -m py_compile "$stage$TTS_GUARD_PATH"
  PYTHONPYCACHEPREFIX="$stage/pycache" /usr/bin/python3 -m py_compile "$stage$CHAT_CLIENT_PATH"
  PYTHONPYCACHEPREFIX="$stage/pycache" /usr/bin/python3 -m py_compile "$stage$CAPACITY_PATH"
  PYTHONPYCACHEPREFIX="$stage/pycache" /usr/bin/python3 -m py_compile "$stage$RELOAD_PATH"
  PYTHONPYCACHEPREFIX="$stage/pycache" /usr/bin/python3 -m py_compile "$stage$DEBUG_CONSOLE_PATH"
  PYTHONPYCACHEPREFIX="$stage/pycache" /usr/bin/python3 -m py_compile "$stage$PERFORMANCE_REPORT_PATH"
  /usr/bin/python3 "$stage$AGENT_PATH" self-test >/dev/null
  [[ "$(/usr/bin/python3 "$stage$CHAT_CLIENT_PATH" --version)" == "2.5.1" ]]
  /usr/bin/python3 "$stage$CAPACITY_PATH" --self-test >/dev/null
  /usr/bin/python3 "$stage$DEBUG_CONSOLE_PATH" --self-test >/dev/null
  /usr/bin/python3 "$stage$PERFORMANCE_REPORT_PATH" --self-test >/dev/null
  /usr/bin/python3 "$stage$AGENT_PATH" check-config --config "$stage$CONFIG_FILE" >/dev/null
  /usr/bin/python3 "$stage$CAPACITY_PATH" --check-config --config "$stage$CONFIG_FILE" >/dev/null

  capture_service_states
  backup_asterisk
  INSTALL_STARTED="y"
  trap on_install_error ERR

  # Prevent new telephone turns while the one-time clips are generated.
  for index in 0 1 2; do
    if systemctl cat "kienzlefon-ai-agent@${index}.service" >/dev/null 2>&1; then
      systemctl stop "kienzlefon-ai-agent@${index}.service"
    fi
  done
  if [[ "$FILLER_ENABLED" == "true" ]]; then
    /usr/bin/python3 "$stage$AGENT_PATH" prepare-filler --config "$stage$CONFIG_FILE" \
      --filler-output "$stage$FILLER_DIR"
    install -d -m 0755 "$INSTALL_ROOT/audio" "$FILLER_DIR"
    for name in 01-bitte-warten.pcm 02-ich-verarbeite.pcm 03-bitte-warten.pcm manifest.json; do
      install -m 0644 "$stage$FILLER_DIR/$name" "$FILLER_DIR/$name"
    done
  fi

  install -m 0640 "$stage$CONFIG_FILE" "$CONFIG_FILE"
  install -m 0755 "$stage$AGENT_PATH" "$AGENT_PATH"
  install -m 0644 "$stage$TTS_GUARD_PATH" "$TTS_GUARD_PATH"
  install -m 0755 "$stage$CHAT_CLIENT_PATH" "$CHAT_CLIENT_PATH"
  install_chat_command
  install -m 0755 "$stage$CAPACITY_PATH" "$CAPACITY_PATH"
  install -m 0755 "$stage$RELOAD_PATH" "$RELOAD_PATH"
  install -m 0755 "$stage$DEBUG_CONSOLE_PATH" "$DEBUG_CONSOLE_PATH"
  install -m 0755 "$stage$PERFORMANCE_REPORT_PATH" "$PERFORMANCE_REPORT_PATH"
  install -m 0640 "$stage$ASTERISK_ETC/pjsip.conf" "$ASTERISK_ETC/pjsip.conf"
  install -m 0640 "$stage$ASTERISK_ETC/extensions.conf" "$ASTERISK_ETC/extensions.conf"
  install -m 0644 "$stage$UNIT_FILE" "$UNIT_FILE"
  install -m 0644 "$stage$CAPACITY_UNIT_FILE" "$CAPACITY_UNIT_FILE"
  install -m 0644 "$stage$TEXT_UNIT_FILE" "$TEXT_UNIT_FILE"
  chown "root:${ASTERISK_RUNTIME_GROUP}" \
    "$CONFIG_FILE" "$ASTERISK_ETC/pjsip.conf" "$ASTERISK_ETC/extensions.conf" \
    "$STATE_DIR" "$STATE_DIR/commits" "$PERFORMANCE_LOG_DIR"

  systemctl disable --now kienzlefon-worker.service >/dev/null 2>&1 || true
  systemctl disable --now kienzlefon-admission-listener.service >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl restart asterisk.service
  systemctl enable kienzlefon-ai-capacity-publisher.service
  systemctl restart kienzlefon-ai-capacity-publisher.service
  systemctl enable kienzlefon-ai-text.service
  systemctl restart kienzlefon-ai-text.service
  for index in 0 1 2; do
    systemctl enable "kienzlefon-ai-agent@${index}.service"
    systemctl restart "kienzlefon-ai-agent@${index}.service"
  done
  sleep 1
  check_installed
  # Private last-known-good configuration for transactional future reloads.
  [[ ! -L "$STATE_DIR/last-reload.toml" ]] || die "Last reload configuration must not be a symlink."
  install -m 0600 "$CONFIG_FILE" "$STATE_DIR/last-reload.toml"
  INSTALL_STARTED="n"
  trap - ERR
  sep "${PRODUCT} v${INSTALLER_VERSION} installed"
  printf 'Three SIP clients: 8810, 8811, 8812\n'
  printf 'Three AI agents: ai-slot-00, ai-slot-01, ai-slot-02\n'
  printf 'Media: AudioSocket slin16/0x12 at 16 kHz; SIP prefers G.722 with G.711 fallback\n'
  printf 'Configuration: %s\n' "$CONFIG_FILE"
  printf 'Reload command: sudo kienzlefon-ai-reload\n'
  printf 'Debug console: sudo kienzlefon-ai-debug-console\n'
  printf 'Performance report: sudo kienzlefon-ai-performance-report\n'
  printf 'Block ASR: enabled; speculative LLM: disabled\nStatic filler audio: %s\n' "$FILLER_ENABLED"
  printf 'Persistent local chat: kienzlefon-chat\n'
  printf 'Backup: %s\n' "$BACKUP_DIR"
  printf 'SIP passwords were not printed.\n'
  printf 'Capacity publication: kienzlefon-ai-capacity-publisher.service\n'
  printf 'Local text interface: http://127.0.0.1:%s (kienzlefon-ai-text.service)\n' "$TEXT_API_PORT"
}

check_installed() {
  local failed=0 index registrations endpoint_detail readiness_ok="n" attempt=0
  local socket_available agent_socket readiness_detail="" readiness_code="readiness_check_failed"
  [[ -r "$CONFIG_FILE" ]] || { printf 'FAIL: backend configuration missing\n' >&2; return 1; }
  [[ -x "$AGENT_PATH" ]] || { printf 'FAIL: agent executable missing\n' >&2; return 1; }
  [[ -r "$TTS_GUARD_PATH" ]] || { printf 'FAIL: TTS guard missing\n' >&2; return 1; }
  [[ -x "$CHAT_CLIENT_PATH" ]] || { printf 'FAIL: chat client missing\n' >&2; return 1; }
  [[ -L "$CHAT_COMMAND_PATH" && "$(readlink -- "$CHAT_COMMAND_PATH")" == "$CHAT_CLIENT_PATH" ]] \
    || { printf 'FAIL: system-wide chat command is missing or unmanaged\n' >&2; return 1; }
  [[ "$("$CHAT_COMMAND_PATH" --version)" == "2.5.1" ]] \
    || { printf 'FAIL: chat client version mismatch\n' >&2; return 1; }
  [[ -x "$CAPACITY_PATH" ]] || { printf 'FAIL: capacity publisher missing\n' >&2; return 1; }
  [[ -x "$RELOAD_PATH" ]] || { printf 'FAIL: reload command missing\n' >&2; return 1; }
  [[ -x "$DEBUG_CONSOLE_PATH" ]] || { printf 'FAIL: debug console missing\n' >&2; return 1; }
  [[ -x "$PERFORMANCE_REPORT_PATH" ]] || { printf 'FAIL: performance report missing\n' >&2; return 1; }
  [[ "$(grep -c '^allow=g722,alaw,ulaw$' "$ASTERISK_ETC/pjsip.conf" || true)" == "3" ]] \
    || { printf 'FAIL: three G.722-capable PJSIP endpoints are not installed\n' >&2; failed=1; }
  [[ "$(grep -c 'Dial(AudioSocket/.*c(slin16))' "$ASTERISK_ETC/extensions.conf" || true)" == "3" ]] \
    || { printf 'FAIL: three slin16 AudioSocket dial paths are not installed\n' >&2; failed=1; }
  /usr/bin/python3 - "$AGENT_PATH" <<'PY' || failed=1
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
compile(source, sys.argv[1], "exec")
PY
  /usr/bin/python3 "$AGENT_PATH" self-test >/dev/null || failed=1
  /usr/bin/python3 "$AGENT_PATH" check-config --config "$CONFIG_FILE" >/dev/null || failed=1
  if [[ "$FILLER_ENABLED" == "true" ]]; then
    /usr/bin/python3 "$AGENT_PATH" check-filler --config "$CONFIG_FILE" >/dev/null || failed=1
  fi
  /usr/bin/python3 "$CAPACITY_PATH" --self-test >/dev/null || failed=1
  /usr/bin/python3 "$CAPACITY_PATH" --check-config --config "$CONFIG_FILE" >/dev/null || failed=1
  /usr/bin/python3 "$DEBUG_CONSOLE_PATH" --self-test >/dev/null || failed=1
  /usr/bin/python3 "$PERFORMANCE_REPORT_PATH" --self-test >/dev/null || failed=1
  systemctl is-active --quiet asterisk.service || { printf 'FAIL: Asterisk is not active\n' >&2; failed=1; }
  if ((failed == 0)); then
    verify_asterisk_wideband || failed=1
  fi
  systemctl is-active --quiet kienzlefon-ai-capacity-publisher.service \
    || { printf 'FAIL: capacity publisher is not active\n' >&2; failed=1; }
  systemctl is-active --quiet kienzlefon-ai-text.service \
    || { printf 'FAIL: local text interface is not active\n' >&2; failed=1; }
  [[ -S "${RUNTIME_DIR}/text/control.sock" ]] \
    || { printf 'FAIL: chat debug socket is not available\n' >&2; failed=1; }
  /usr/bin/python3 - "$TEXT_API_PORT" <<'PY' || {
import json, sys, urllib.request
with urllib.request.urlopen(
    f"http://127.0.0.1:{int(sys.argv[1])}/health", timeout=2.0
) as response:
    value = json.load(response)
if value.get("ok") is not True or value.get("version") != "2.5.1":
    raise SystemExit(1)
PY
    printf 'FAIL: local text interface health check failed\n' >&2
    failed=1
  }
  if systemctl is-active --quiet kienzlefon-worker.service; then
    printf 'FAIL: legacy Kienzlefon worker would start a second ASR instance\n' >&2
    failed=1
  fi
  if systemctl is-active --quiet kienzlefon-admission-listener.service; then
    printf 'FAIL: legacy admission listener is still active on the dedicated backend\n' >&2
    failed=1
  fi
  for index in 0 1 2; do
    systemctl is-active --quiet "kienzlefon-ai-agent@${index}.service" \
      || { printf 'FAIL: agent slot %s is not active\n' "$index" >&2; failed=1; }
    socket_available="n"
    agent_socket="${RUNTIME_DIR}/slot-${index}/control.sock"
    attempt=0
    while ((attempt < 80)); do
      if [[ -S "$agent_socket" ]] \
         && "$AGENT_PATH" status --config "$CONFIG_FILE" --slot-index "$index" \
              >/dev/null 2>&1; then
        socket_available="y"
        break
      fi
      attempt=$((attempt + 1))
      sleep 0.25
    done
    [[ "$socket_available" == "y" ]] \
      || { printf 'FAIL: agent slot %s control socket is unavailable\n' "$index" >&2; failed=1; }
  done
  if ((failed == 0)); then
    attempt=0
    while ((attempt < 90)); do
      if readiness_detail="$("$RELOAD_PATH" --check 2>&1)"; then
        readiness_ok="y"
        break
      fi
      if [[ "$readiness_detail" =~ RELOAD_FAIL[[:space:]]code=([A-Za-z0-9._:-]+) ]]; then
        readiness_code="${BASH_REMATCH[1]}"
      else
        readiness_code="readiness_check_failed"
      fi
      attempt=$((attempt + 1))
      sleep 0.5
    done
    [[ "$readiness_ok" == "y" ]] \
      || { printf 'FAIL: SIP/listener readiness check failed code=%s\n' \
            "$readiness_code" >&2; failed=1; }
  fi
  registrations="$(asterisk -rx 'pjsip show registrations' 2>/dev/null || true)"
  for index in 0 1 2; do
    grep -q "ai-slot-0${index}-registration" <<<"$registrations" \
      || { printf 'FAIL: PJSIP registration object for slot %s missing\n' "$index" >&2; failed=1; }
    endpoint_detail="$(
      asterisk -rx "pjsip show endpoint ai-slot-0${index}-endpoint" 2>/dev/null || true
    )"
    grep -Eq 'allow[[:space:]]*:[[:space:]]*\([^)]*g722' <<<"$endpoint_detail" \
      || { printf 'FAIL: PJSIP endpoint for slot %s does not allow G.722\n' "$index" >&2; failed=1; }
  done
  ((failed == 0)) || return 1
  printf '%s v%s: local checks passed.\n' "$PRODUCT" "$INSTALLER_VERSION"
  printf 'All SIP registrations and the admission listener connection are ready.\n'
}

self_test_installer() {
  local test_root temp_root prompt_file agent tts_guard chat_client publisher reload_command debug_console performance_report pjsip extensions
  local unit capacity_unit text_unit custom_unit candidate test_python="" fake_bin fake_modules
  local link_root link_command legacy_target current_target unmanaged_target escape_target resolved_target
  test_root="$(mktemp -d /tmp/kienzlefon-ai-backend-selftest.XXXXXX)"
  [[ "$QWEN_SPEAKER" == "uncle_fu" ]]
  [[ "$SPEECH_END_MS" == "500" ]]
  [[ "$DEBUG_ALLOW_SENSITIVE_CONSOLE" == "false" ]]
  [[ "$PERFORMANCE_ENABLED" == "false" ]]
  [[ "$STREAMING_ASR" == "false" ]]
  [[ "$SPECULATIVE_LLM" == "false" ]]
  [[ "$FILLER_ENABLED" == "true" ]]
  [[ "$GREETING" == "Ich bin Karl der elektronische Praxisassistent. Bitte Sprechen Sie in natürlicher Sprache einfach drauf los. Wie kann ich Ihnen bitte helfen?" ]]
  TEMP_DIRS+=("$test_root")
  temp_root="$test_root/render"
  (
    BACKUP_DIR="$test_root/filler-backup"
    install -d -m 0700 "$BACKUP_DIR/backend" "$test_root/filler-fixture"
    for name in 01-bitte-warten.pcm 02-ich-verarbeite.pcm 03-bitte-warten.pcm manifest.json; do
      fixture="$test_root/filler-fixture/$name"
      printf 'synthetic-old\n' >"$fixture"
      backup_optional_file "$fixture" "filler-$name"
      printf 'synthetic-new\n' >"$fixture"
      restore_optional_file "$fixture" "filler-$name"
      [[ "$(<"$fixture")" == "synthetic-old" ]]
    done
    fixture="$test_root/filler-fixture/previously-absent.pcm"
    backup_optional_file "$fixture" filler-absent
    printf 'synthetic-new\n' >"$fixture"
    restore_optional_file "$fixture" filler-absent
    [[ ! -e "$fixture" ]]
  )
  printf 'filler file backup/restore self-test: ok\n'
  prompt_file="$test_root/system-prompt.txt"
  fake_bin="$test_root/fake-bin"
  fake_modules="$test_root/fake-modules"
  install -d -m 0750 "$fake_bin" "$fake_modules"
  : >"$fake_modules/res_audiosocket.so"
  link_root="$test_root/chat-link"
  link_command="$link_root/usr/local/bin/kienzlefon-chat"
  legacy_target="$link_root/usr/local/lib/kienzlefon-chat/kienzlefon-chat-client-v1.0.py"
  current_target="$link_root/opt/kienzlefon-ai-asterisk-backend/bin/kienzlefon_chat.py"
  unmanaged_target="$link_root/unmanaged.py"
  escape_target="$link_root/usr/local/lib/kienzlefon-chat/kienzlefon-chat-client-v9.9.py"
  install -d -m 0755 "$(dirname "$link_command")" "$(dirname "$legacy_target")" \
    "$(dirname "$current_target")"
  : >"$legacy_target"
  : >"$current_target"
  : >"$unmanaged_target"
  legacy_target="$(resolve_existing_path "$legacy_target")"
  current_target="$(resolve_existing_path "$current_target")"
  unmanaged_target="$(resolve_existing_path "$unmanaged_target")"
  ln -s ../lib/kienzlefon-chat/kienzlefon-chat-client-v1.0.py "$link_command"
  resolved_target="$(resolve_existing_path "$link_command")"
  [[ "$resolved_target" == "$legacy_target" ]]
  chat_target_is_managed "$resolved_target" "$current_target" "$(dirname "$legacy_target")"
  rm "$link_command"
  ln -s "$current_target" "$link_command"
  resolved_target="$(resolve_existing_path "$link_command")"
  chat_target_is_managed "$resolved_target" "$current_target" "$(dirname "$legacy_target")"
  rm "$link_command"
  ln -s "$unmanaged_target" "$link_command"
  resolved_target="$(resolve_existing_path "$link_command")"
  if chat_target_is_managed "$resolved_target" "$current_target" "$(dirname "$legacy_target")"; then
    die "Chat command self-test accepted an unmanaged target."
  fi
  rm "$link_command"
  ln -s "$unmanaged_target" "$escape_target"
  ln -s ../lib/kienzlefon-chat/kienzlefon-chat-client-v9.9.py "$link_command"
  resolved_target="$(resolve_existing_path "$link_command")"
  if chat_target_is_managed "$resolved_target" "$current_target" "$(dirname "$legacy_target")"; then
    die "Chat command self-test accepted a managed-name symlink escaping its directory."
  fi
  rm "$link_command"
  ln -s "$link_root/missing.py" "$link_command"
  if resolve_existing_path "$link_command" >/dev/null 2>&1; then
    die "Chat command self-test accepted a broken target."
  fi
  printf 'chat command migration self-test: ok\n'
  cat >"$fake_bin/asterisk" <<'SH'
#!/usr/bin/env bash
set -eu
case "${2:-}" in
  'module show like audiosocket')
    printf '%s\n' 'app_audiosocket.so Running' 'chan_audiosocket.so Running' 'res_audiosocket.so Running'
    ;;
  'module show like codec_g722')
    if [[ "${KZF_TEST_NO_G722:-n}" == "y" ]]; then
      printf '%s\n' '0 modules loaded'
    else
      printf '%s\n' 'codec_g722.so Running'
    fi
    ;;
  'core show application Dial')
    if [[ "${KZF_TEST_NO_DIAL:-n}" == "y" ]]; then
      printf '%s\n' 'Your application(s) is (are) not registered.'
    else
      printf "%s\n" "-= Info about application 'Dial' =-"
      for ((line = 0; line < 12000; line++)); do
        printf '%s\n' 'Synthetic long Dial application documentation.'
      done
    fi
    ;;
  'core show function UUID')
    if [[ "${KZF_TEST_NO_UUID:-n}" == "y" ]]; then
      printf '%s\n' 'No function by that name registered.'
    else
      printf "%s\n" "-= Info about function 'UUID' =-"
      for ((line = 0; line < 4000; line++)); do
        printf '%s\n' 'Synthetic long UUID function documentation.'
      done
    fi
    ;;
  'core show codecs audio')
    printf '%s\n' '11 audio slin slin16 Signed Linear' '24 audio g722 g722 G722'
    ;;
  'core show translation paths slin 16000') printf '%s\n' 'To g722:16000 : direct' ;;
  'core show translation paths g722 16000') printf '%s\n' 'To slin:16000 : direct' ;;
  'core show settings') printf '  Module directory: %s\n' "${KZF_TEST_MODULE_DIR:?}" ;;
  *) exit 1 ;;
esac
SH
  cat >"$fake_bin/nm" <<'SH'
#!/usr/bin/env bash
set -eu
if [[ "${KZF_TEST_NO_SLIN16:-n}" == "y" ]]; then
  printf '%s\n' '                 U ast_format_slin'
else
  printf '%s\n' '                 U ast_format_slin16'
fi
SH
  chmod 0755 "$fake_bin/asterisk" "$fake_bin/nm"
  (
    PATH="$fake_bin:$PATH" verify_asterisk_call_primitives
  )
  if (
    PATH="$fake_bin:$PATH" KZF_TEST_NO_DIAL="y" \
      verify_asterisk_call_primitives >/dev/null 2>&1
  ); then
    die "Call primitive self-test accepted missing app_dial."
  fi
  if (
    PATH="$fake_bin:$PATH" KZF_TEST_NO_UUID="y" \
      verify_asterisk_call_primitives >/dev/null 2>&1
  ); then
    die "Call primitive self-test accepted missing func_uuid."
  fi
  (
    PATH="$fake_bin:$PATH" KZF_TEST_MODULE_DIR="$fake_modules" \
      verify_asterisk_wideband
  )
  if (
    PATH="$fake_bin:$PATH" KZF_TEST_MODULE_DIR="$fake_modules" \
      KZF_TEST_NO_G722="y" verify_asterisk_wideband >/dev/null 2>&1
  ); then
    die "Wideband capability self-test accepted missing codec_g722."
  fi
  if (
    PATH="$fake_bin:$PATH" KZF_TEST_MODULE_DIR="$fake_modules" \
      KZF_TEST_NO_SLIN16="y" verify_asterisk_wideband >/dev/null 2>&1
  ); then
    die "Wideband capability self-test accepted an 8 kHz res_audiosocket."
  fi
  MAIN_HOST="127.0.0.2"
  LISTENER_HOST="127.0.0.2"
  BACKEND_BIND_IP="127.0.0.1"
  MAIN_PORT="5060"
  SIP_PASSWORD_0="AAAAAAAAAAAAAAAAAAAA0000"
  SIP_PASSWORD_1="BBBBBBBBBBBBBBBBBBBB1111"
  SIP_PASSWORD_2="CCCCCCCCCCCCCCCCCCCC2222"
  HTTP_TIMEOUT_SECONDS="61"
  ASR_TIMEOUT_SECONDS="62"
  QWEN_SEED="99"
  MAX_TURNS="17"
  MAX_LLM_TOKENS="777"
  TEMPERATURE="0.2"
  ENERGY_THRESHOLD="621"
  DEBUG_ALLOW_SENSITIVE_CONSOLE="true"
  DEBUG_METRICS_INTERVAL_MS="375"
  PERFORMANCE_ENABLED="true"
  PERFORMANCE_MAX_BYTES="1048576"
  PERFORMANCE_BACKUP_COUNT="3"
  SNAPSHOT_INTERVAL_MS="1100"
  LEASE_TTL_MS="5100"
  printf 'Konfigurierter Selbsttest-Prompt\nmit zweiter Zeile.\n' >"$prompt_file"
  SYSTEM_PROMPT_FILE="$prompt_file"
  SYSTEM_PROMPT_FILE_SET="y"
  load_system_prompt_file
  validate_configuration
  render_tree "$temp_root"
  MAIN_HOST=""
  BACKEND_BIND_IP=""
  SIP_PASSWORD_0=""; SIP_PASSWORD_1=""; SIP_PASSWORD_2=""
  HTTP_TIMEOUT_SECONDS="45"; ASR_TIMEOUT_SECONDS="45"
  QWEN_SEED="42"; MAX_TURNS="14"; MAX_LLM_TOKENS="700"; TEMPERATURE="0.1"
  ENERGY_THRESHOLD="520"; SNAPSHOT_INTERVAL_MS="1000"; LEASE_TTL_MS="5000"
  DEBUG_ALLOW_SENSITIVE_CONSOLE="false"; DEBUG_METRICS_INTERVAL_MS="250"
  PERFORMANCE_ENABLED="false"; PERFORMANCE_MAX_BYTES="10485760"; PERFORMANCE_BACKUP_COUNT="5"
  SYSTEM_PROMPT="not-preserved"; SYSTEM_PROMPT_FILE_SET="n"
  LISTENER_HOST=""; LISTENER_HOST_SET="n"
  STREAMING_ASR="false"
  EXISTING_CONFIG_LOADED="n"
  load_existing_config "$temp_root$CONFIG_FILE"
  [[ "$EXISTING_CONFIG_LOADED" == "y" ]]
  [[ "$STREAMING_ASR" == "false" ]]
  (
    STREAMING_ASR="false"
    write_backend_config "$test_root/streaming-off.toml"
    STREAMING_ASR="true"
    load_existing_config "$test_root/streaming-off.toml"
    [[ "$STREAMING_ASR" == "false" ]]
    SPECULATIVE_LLM="false"
    write_backend_config "$test_root/speculative-off.toml"
    SPECULATIVE_LLM="true"
    load_existing_config "$test_root/speculative-off.toml"
    [[ "$SPECULATIVE_LLM" == "false" ]]
    sed '/^speculative_llm = /d' "$test_root/speculative-off.toml" >"$test_root/pre-speculative-config.toml"
    load_existing_config "$test_root/pre-speculative-config.toml"
    [[ "$SPECULATIVE_LLM" == "false" ]]
    sed '/^streaming_asr = /d' "$test_root/streaming-off.toml" >"$test_root/legacy-config.toml"
    load_existing_config "$test_root/legacy-config.toml"
    [[ "$STREAMING_ASR" == "false" ]]
    STREAMING_ASR="true"
    SPECULATIVE_LLM="true"
    FILLER_ENABLED="false"
    write_backend_config "$test_root/old-streaming-config.toml"
    FILLER_ENABLED="true"
    load_existing_config "$test_root/old-streaming-config.toml"
    [[ "$STREAMING_ASR" == "false" && "$SPECULATIVE_LLM" == "false" ]]
    [[ "$FILLER_ENABLED" == "false" ]]
    FILLER_SEED="54321"
    write_backend_config "$test_root/filler-seed.toml"
    FILLER_SEED="12345"
    load_existing_config "$test_root/filler-seed.toml"
    [[ "$FILLER_SEED" == "54321" && "$QWEN_SEED" == "99" ]]
    sed '/^seed = /d' "$test_root/filler-seed.toml" >"$test_root/legacy-filler-seed.toml"
    load_existing_config "$test_root/legacy-filler-seed.toml"
    [[ "$FILLER_SEED" == "12345" && "$QWEN_SEED" == "99" ]]
    FILLER_OPTIONS='{"part1_text":"", "part2_text":"Test \"zwei\"", "part3_text":"Danke.", "part1_start_ms":0, "part2_start_ms":3000, "part3_start_ms":5000, "regenerate_on_reload":false, "beep_enabled":false, "beep_start_ms":200, "beep_interval_ms":1200, "beep_frequency_hz":500, "beep_duration_ms":80, "beep_volume":0.1}'
    write_backend_config "$test_root/custom-filler.toml"
    FILLER_OPTIONS='{}'
    load_existing_config "$test_root/custom-filler.toml"
    FILLER_OPTIONS="$FILLER_OPTIONS" python3 - <<'PY'
import json, os
raw = json.loads(os.environ["FILLER_OPTIONS"])
assert raw["part1_text"] == "" and raw["part2_text"] == 'Test "zwei"'
assert raw["part3_start_ms"] == 5000 and raw["beep_volume"] == 0.1
assert raw["regenerate_on_reload"] is False and raw["beep_enabled"] is False
PY
  )
  [[ "$HTTP_TIMEOUT_SECONDS" == "61" && "$ASR_TIMEOUT_SECONDS" == "62" ]]
  [[ "$QWEN_SEED" == "99" && "$MAX_TURNS" == "17" && "$MAX_LLM_TOKENS" == "777" ]]
  [[ "$TEMPERATURE" == "0.2" && "$ENERGY_THRESHOLD" == "621" ]]
  [[ "$DEBUG_ALLOW_SENSITIVE_CONSOLE" == "true" && "$DEBUG_METRICS_INTERVAL_MS" == "375" ]]
  [[ "$PERFORMANCE_ENABLED" == "true" && "$PERFORMANCE_MAX_BYTES" == "1048576" ]]
  [[ "$PERFORMANCE_BACKUP_COUNT" == "3" ]]
  DEBUG_ALLOW_SENSITIVE_CONSOLE="false"
  DEBUG_ALLOW_SENSITIVE_CONSOLE_SET="y"
  load_existing_config "$temp_root$CONFIG_FILE"
  [[ "$DEBUG_ALLOW_SENSITIVE_CONSOLE" == "false" ]]
  DEBUG_ALLOW_SENSITIVE_CONSOLE_SET="n"
  [[ "$SNAPSHOT_INTERVAL_MS" == "1100" && "$LEASE_TTL_MS" == "5100" ]]
  [[ "$SYSTEM_PROMPT" == $'Konfigurierter Selbsttest-Prompt\nmit zweiter Zeile.' ]]
  (
    NON_INTERACTIVE="n"
    collect_configuration </dev/null >/dev/null 2>&1
  )
  printf 'existing configuration reuse self-test: ok\n'
  agent="$temp_root$AGENT_PATH"
  tts_guard="$temp_root$TTS_GUARD_PATH"
  chat_client="$temp_root$CHAT_CLIENT_PATH"
  publisher="$temp_root$CAPACITY_PATH"
  reload_command="$temp_root$RELOAD_PATH"
  debug_console="$temp_root$DEBUG_CONSOLE_PATH"
  performance_report="$temp_root$PERFORMANCE_REPORT_PATH"
  pjsip="$temp_root$ASTERISK_ETC/pjsip.conf"
  extensions="$temp_root$ASTERISK_ETC/extensions.conf"
  unit="$temp_root$UNIT_FILE"
  capacity_unit="$temp_root$CAPACITY_UNIT_FILE"
  text_unit="$temp_root$TEXT_UNIT_FILE"
  custom_unit="$temp_root/custom-agent.service"
  write_systemd_unit \
    "$custom_unit" /var/spool/kienzlefon /srv/telepraxis/test/inbox pbx-runtime
  grep -Fxq 'Group=pbx-runtime' "$custom_unit"
  for candidate in /usr/local/bin/python3 /opt/homebrew/bin/python3.13 /usr/bin/python3; do
    if [[ -x "$candidate" ]] \
       && "$candidate" -c 'import tomllib; assert __import__("sys").version_info >= (3, 11)' >/dev/null 2>&1; then
      test_python="$candidate"
      break
    fi
  done
  [[ -n "$test_python" ]] || die "Self-test requires an available Python 3.11+ interpreter."
  PYTHONPYCACHEPREFIX="$temp_root/pycache" "$test_python" -m py_compile "$agent"
  PYTHONPYCACHEPREFIX="$temp_root/pycache" "$test_python" -m py_compile "$tts_guard"
  PYTHONPYCACHEPREFIX="$temp_root/pycache" "$test_python" -m py_compile "$chat_client"
  PYTHONPYCACHEPREFIX="$temp_root/pycache" "$test_python" -m py_compile "$publisher"
  PYTHONPYCACHEPREFIX="$temp_root/pycache" "$test_python" -m py_compile "$reload_command"
  PYTHONPYCACHEPREFIX="$temp_root/pycache" "$test_python" -m py_compile "$debug_console"
  PYTHONPYCACHEPREFIX="$temp_root/pycache" "$test_python" -m py_compile "$performance_report"
  "$test_python" "$agent" self-test
  [[ "$("$test_python" "$chat_client" --version)" == "2.5.1" ]]
  "$test_python" "$chat_client" --help >/dev/null
  "$test_python" "$agent" check-config --config "$temp_root$CONFIG_FILE"
  "$test_python" "$publisher" --self-test
  "$test_python" "$publisher" --check-config --config "$temp_root$CONFIG_FILE"
  "$test_python" "$debug_console" --self-test
  [[ "$("$test_python" "$debug_console" --version)" == *" 2.5.1" ]]
  "$test_python" "$debug_console" --help >/dev/null
  "$test_python" "$performance_report" --self-test
  [[ "$("$test_python" "$performance_report" --version)" == *" 2.5.1" ]]
  "$test_python" "$performance_report" --help >/dev/null
  "$test_python" - "$temp_root$CONFIG_FILE" "$pjsip" "$extensions" "$unit" \
    "$capacity_unit" "$text_unit" "$publisher" "$reload_command" "$debug_console" "$performance_report" "$agent" \
    "$tts_guard" "$chat_client" <<'PY'
import importlib.util, re, sys, tomllib
from pathlib import Path
(
    config_path, pjsip_path, extensions_path, unit_path, capacity_unit_path,
    text_unit_path, publisher_path, reload_path, debug_console_path, performance_report_path, agent_path,
    tts_guard_path, chat_client_path,
) = sys.argv[1:]
with open(config_path, "rb") as handle:
    config = tomllib.load(handle)
assert config["backend"]["slot_count"] == 3
assert config["sip"]["extensions"] == ["8810", "8811", "8812"]
assert len(set(config["sip"]["passwords"])) == 3
assert config["dialog"]["system_prompt"] == "Konfigurierter Selbsttest-Prompt\nmit zweiter Zeile."
assert config["dialog"]["streaming_asr"] is False
assert config["dialog"]["speculative_llm"] is False
assert config["filler"]["enabled"] is True
assert config["filler"]["seed"] == 12345
assert config["dialog"]["qwen_speaker"] == "uncle_fu"
assert config["dialog"]["greeting"] == (
    "Ich bin Karl der elektronische Praxisassistent. Bitte Sprechen Sie in "
    "natürlicher Sprache einfach drauf los. Wie kann ich Ihnen bitte helfen?"
)
assert config["dialog"]["telephone_overlay"].startswith(
    "Der aktuelle Telefonzustand/Call-Policy ist die einzige Wahrheit"
)
assert config["dialog"]["chat_overlay"].startswith("Kanal: chat")
assert config["text_api"] == {"enabled": True, "bind": "127.0.0.1", "port": 8300}
assert config["vad"]["speech_end_ms"] == 500
assert config["debug"] == {
    "allow_sensitive_console": True,
    "metrics_interval_ms": 375,
}
assert config["performance"] == {
    "enabled": True,
    "log_file": "/var/log/kienzlefon-ai-asterisk-backend/performance.jsonl",
    "max_bytes": 1048576,
    "backup_count": 3,
}
assert config["admission"] == {
    "enabled": True,
    "listener_host": "127.0.0.2",
    "listener_port": 8190,
    "publisher_id": "kienzlefon-ai-asterisk-backend",
    "snapshot_interval_ms": 1100,
    "lease_ttl_ms": 5100,
    "connect_timeout_ms": 1000,
    "control_socket": "/run/kienzlefon-ai-integration/capacity-control.sock",
    "asr_phone_capacity": 3,
}
pjsip = Path(pjsip_path).read_text(encoding="utf-8")
extensions = Path(extensions_path).read_text(encoding="utf-8")
unit = Path(unit_path).read_text(encoding="utf-8")
capacity_unit = Path(capacity_unit_path).read_text(encoding="utf-8")
text_unit = Path(text_unit_path).read_text(encoding="utf-8")
publisher = Path(publisher_path).read_text(encoding="utf-8")
reload_command = Path(reload_path).read_text(encoding="utf-8")
debug_console = Path(debug_console_path).read_text(encoding="utf-8")
performance_report = Path(performance_report_path).read_text(encoding="utf-8")
agent = Path(agent_path).read_text(encoding="utf-8")
sys.path.insert(0, str(Path(agent_path).parent))
spec = importlib.util.spec_from_file_location("kzf_filler_config_test", agent_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
assert module.load_config(config_path).filler_enabled is True
assert module.load_config(config_path).filler_seed == 12345
original_config = Path(config_path).read_text(encoding="utf-8")
candidate = Path(config_path).with_name("filler-config-test.toml")
for old, new, valid in (
    ("streaming_asr = false", "streaming_asr = true", False),
    ("speculative_llm = false", "speculative_llm = true", False),
    ("[filler]\n", "[unused_filler]\n", True),
    ("enabled = true\n\n[text_api]", "enabled = false\n\n[text_api]", True),
    ("enabled = true\n\n[text_api]", 'enabled = "false"\n\n[text_api]', False),
    ("seed = 12345\n", "", True),
    ("seed = 12345\n", "seed = 0\n", True),
    ("seed = 12345\n", "seed = 2147483647\n", True),
    ("seed = 12345\n", "seed = -1\n", False),
    ("seed = 12345\n", "seed = 2147483648\n", False),
    ("seed = 12345\n", "seed = true\n", False),
    ("seed = 12345\n", 'seed = "12345"\n', False),
):
    assert old in original_config
    candidate.write_text(original_config.replace(old, new), encoding="utf-8")
    try:
        loaded = module.load_config(candidate)
    except module.AgentError:
        assert not valid
    else:
        assert valid
        assert loaded.filler_enabled is (new != "enabled = false\n\n[text_api]")
candidate.unlink()
tts_guard = Path(tts_guard_path).read_text(encoding="utf-8")
chat_client = Path(chat_client_path).read_text(encoding="utf-8")
assert len(re.findall(r"^type=registration$", pjsip, re.M)) == 3
assert len(re.findall(r"^type=endpoint$", pjsip, re.M)) == 3
assert all(f"username={extension}" in pjsip for extension in ("8810", "8811", "8812"))
assert pjsip.count("allow=g722,alaw,ulaw") == 3
assert "allow=alaw,ulaw" not in pjsip
assert all(f"127.0.0.1:{port}" in extensions for port in (8290, 8291, 8292))
assert extensions.count("Dial(AudioSocket/") == 3
assert extensions.count("/c(slin16))") == 3
assert extensions.count("KZF_AI_GUARD_ACCEPTED") == 3
for index in range(3):
    block = extensions.split(f"[kienzlefon-ai-slot-{index}-in]", 1)[1].split("\n\n", 1)[0]
    assert block.index("AGI(") < block.index("Answer()") < block.index("Dial(AudioSocket/")
assert not re.search(r"^exten => 881[0-2],1,Goto", extensions, re.M)
assert "ExecStart=/usr/bin/python3" in unit and "%i" in unit
assert "Group=root" in unit
assert "kienzlefon-ai-capacity-publisher.service" in unit
assert "RuntimeDirectory=kienzlefon-ai-asterisk-backend/slot-%i" in unit
assert "LogsDirectory=kienzlefon-ai-asterisk-backend" in unit
assert " /var/log/kienzlefon-ai-asterisk-backend " in unit
assert "ReadWritePaths=/run/kienzlefon-ai-asterisk-backend/slot-%i " in unit
assert "RuntimeDirectory=kienzlefon-ai-asterisk-backend\n" not in unit
assert "RuntimeDirectory=kienzlefon-ai-integration" in capacity_unit
assert "kienzlefon_ai_capacity_publisher.py" in capacity_unit
assert "serve-text" in text_unit and "127.0.0.1" not in text_unit
assert "RuntimeDirectory=kienzlefon-ai-asterisk-backend/text" in text_unit
assert "ReadWritePaths=/run/kienzlefon-ai-asterisk-backend/text " in text_unit
assert " /var/lib/kienzlefon-ai-asterisk-backend " in text_unit
assert " /var/spool/kienzlefon " in text_unit
assert " /srv/telepraxis/test/inbox" in text_unit
assert "active_or_reserved_calls" in reload_command
assert "--check" in reload_command
assert "debug_subscribe" in debug_console and "--show-text" in debug_console
assert 'runtime / "text" / "control.sock"' in debug_console
assert "subscribe_text" in debug_console
assert "SENSITIVE_KEYS" in debug_console and "FORBIDDEN_KEYS" in debug_console
assert "kienzlefon-performance-report-v1" in performance_report
assert "end_of_actual_speech_to_first_reply_audio_ms" in performance_report
assert "claim_lease" in publisher and "publisher_hello" in publisher
assert "capacity_snapshot" in publisher and "lease_not_valid" in publisher
assert agent.index('"command": "claim"') < agent.index('"command": "claim_lease"')
assert agent.index('change_stage("greeting_tts")') < agent.index('change_stage("vad")')
assert 'await speak_guarded(self.config.greeting, purpose="greeting")' in agent
greeting_index = agent.index('await speak_guarded(self.config.greeting, purpose="greeting")')
assert greeting_index \
    < agent.index('self.clear_audio_queue(incoming)', greeting_index) \
    < agent.index('change_stage("vad")')
assert 'config.system_prompt.rstrip()' in agent and "SYSTEM_PROMPT =" not in agent
assert "AUDIO_TYPE_SLIN16 = 0x12" in agent
assert "TELEPHONY_RATE = 16000" in agent
assert "BandlimitedPCMResampler" in agent
assert "kind != AUDIO_TYPE_SLIN16" in agent
assert "windowed_sinc_blackman_32tap" in agent
assert "normalize_tts_text" in tts_guard
assert 'VERSION = "2.5.1"' in chat_client
assert 'PERFORMANCE_SCHEMA = "kienzlefon-performance-v1"' in agent
assert '"program_version": VERSION' in agent
assert "create_session" in chat_client and "recording_mode" in chat_client
assert "system_prompt" in Path(sys.argv[1]).read_text(encoding="utf-8")
assert "AAAAAAAAAAAAAAAAAAAA0000" not in extensions
print("installer render self-test: ok")
PY
  "$test_python" - "$reload_command" <<'PY'
import importlib.util, importlib.machinery, sys
loader = importlib.machinery.SourceFileLoader("kzf_reload_test", sys.argv[1])
spec = importlib.util.spec_from_loader("kzf_reload_test", loader)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
module.ensure_idle([{"slot_id": "ai-slot-00", "state": "idle"}])
try:
    module.ensure_idle([{"slot_id": "ai-slot-00", "state": "reserved"}])
except module.ReloadError as error:
    assert str(error) == "active_or_reserved_calls"
else:
    raise AssertionError("busy reload was not rejected")
print("reload command self-test: ok")
module.feedback_reload_self_test()
PY
  "$test_python" - "$test_root/runtime-lifecycle" <<'PY'
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

runtime = Path(sys.argv[1])

def start_slot(index: int):
    path = runtime / f"slot-{index}" / "control.sock.simulated"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"slot-{index}", encoding="ascii")
    return path

with ThreadPoolExecutor(max_workers=3) as pool:
    slots = list(pool.map(start_slot, range(3)))
assert len(set(slots)) == 3
assert all(path.is_file() for path in slots)

# Simulate systemd stopping and starting only slot 1. Its leaf directory may
# disappear, while the runtime objects of slots 0 and 2 must remain untouched.
slots[1].unlink()
slots[1].parent.rmdir()
slots[1] = start_slot(1)
assert all(path.is_file() for path in slots)
assert [path.read_text(encoding="ascii") for path in slots] == [
    "slot-0", "slot-1", "slot-2"
]
print("independent runtime lifecycle self-test: ok")
PY
}

main() {
  parse_args "$@"
  case "$ACTION" in
    install) install_backend ;;
    check) require_root; check_installed ;;
    self-test) self_test_installer ;;
    render)
      [[ -n "$MAIN_HOST" ]] || MAIN_HOST="127.0.0.2"
      [[ -n "$LISTENER_HOST" ]] || LISTENER_HOST="$MAIN_HOST"
      [[ -n "$BACKEND_BIND_IP" ]] || BACKEND_BIND_IP="127.0.0.1"
      [[ -n "$SIP_PASSWORD_0" ]] || SIP_PASSWORD_0="AAAAAAAAAAAAAAAAAAAA0000"
      [[ -n "$SIP_PASSWORD_1" ]] || SIP_PASSWORD_1="BBBBBBBBBBBBBBBBBBBB1111"
      [[ -n "$SIP_PASSWORD_2" ]] || SIP_PASSWORD_2="CCCCCCCCCCCCCCCCCCCC2222"
      load_system_prompt_file
      validate_configuration
      render_tree "$RENDER_ROOT"
      printf 'Rendered backend tree: %s\n' "$RENDER_ROOT"
      ;;
    *) die "Internal action error." ;;
  esac
}

main "$@"
