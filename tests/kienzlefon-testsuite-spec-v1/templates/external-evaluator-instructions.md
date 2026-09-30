# Externe Kienzlefon-Testauswertung

Bewerte die nachfolgenden Testfälle anhand von Szenario, vollständigem Dialog, erzeugten JSON-/Datensätzen und dem tatsächlich verwendeten Kienzlefon-Prompt.

Prüfe insbesondere:
- Wurde das Anliegen korrekt verstanden und auftragsbezogen gespeichert?
- Sind `complete` und Auftragstrennung semantisch korrekt?
- Wurden bekannte Informationen unnötig erneut erfragt?
- Wurden Korrekturen und letzte Angaben übernommen?
- Wurden Informationen, Praxisregeln, Programmfunktionen, Speicherzustände oder Zukunftsversprechen erfunden?
- Entspricht das Verhalten den kanalabhängigen Regeln (Telefon vs. Chat)?
- Sind alle gesprochenen Assistant-Inhalte in der jeweiligen `reply` enthalten?
- Entstanden aus Unterhaltung/Testanweisungen fälschlich Praxisaufträge?
- Wurde bei Rezepten die Abschlussfrage nur im passenden Kontext eingesetzt?
- Wurden AU-/Weiterleitungsfälle korrekt behandelt?

Gib je Szenario PASS / FAIL / REVIEW, konkrete Fundstellen und eine kurze Begründung aus. Bündele anschließend wiederkehrende Fehler nach Ursache und nenne möglichst kleine Promptänderungen, die mehrere Fehler gleichzeitig beheben, statt viele Sonderregeln hinzuzufügen.
