Dieser mojo-branch ist nicht produktiv einsetzbar, sondern ist
work-in-progress fuer eine moegliche Umstellung von CGI::Application
auf Mojolicious als zugrundeliegendes Micro-Framework.

Wesentliche offene Arbeiten sind:

* Blocking Code identifizieren und in non-blocking Code umwandeln

* Streaming-Ausgabe der Suchergebnisse

* Parallelisierung der sequentiellen Suche

* Umstellung der Nutzung von LWP::UserAgent auf Mojo::UserAgent fuer
  den Zugriff auf externe APIs

* Evaluation der Umstellung von datumzentrischen Aktionen auf Mojo::Date

* Evaluation der Umstellung von XML-zentrischen Aktionen auf Mojo::DOM
