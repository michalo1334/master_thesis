# Propozycja tematu pracy dyplomowej — DRAFT

## Proponowany temat pracy dyplomowej w języku polskim

Grafowa symulacja ścieżek ataku i automatyczna optymalizacja obrony w celu minimalizacji zasięgu rażenia w sieciach komputerowych

## Proponowany temat pracy dyplomowej w języku angielskim

Graph-Based Attack Path Simulation and Automated Defense Optimization for Blast Radius Minimization in Computer Networks

## Cel pracy

Opracowanie i ewaluacja systemu opartego na grafach ataku, który symuluje propagację zagrożeń w sieciach komputerowych i automatycznie rekomenduje działania obronne (segmentację sieci, kolejność łatania podatności) minimalizujące zasięg rażenia ataku. System zostanie porównany z metodami konwencjonalnymi, w tym priorytetyzacją na podstawie wyników CVSS.

## Aspekt badawczy pracy

Zbadanie, w jakim stopniu grafowa symulacja ścieżek ataku połączona z algorytmami optymalizacji obrony (min-cut dla segmentacji, zachłanna priorytetyzacja łatek) redukuje zasięg rażenia ataków sieciowych w porównaniu z konwencjonalnymi metodami priorytetyzacji podatności. Badanie obejmuje trzy pytania szczegółowe: (1) skuteczność modelowania grafowego w odwzorowaniu realnych wzorców ruchu lateralnego, (2) porównanie strategii optymalizacyjnych pod kątem redukcji zasięgu rażenia na jednostkę działania obronnego, (3) skalowalność podejścia przy rosnącym rozmiarze sieci. Ewaluacja ilościowa na syntetycznych topologiach sieciowych z wykorzystaniem symulacji Monte Carlo.

## Streszczenie

Praca dotyczy problemu minimalizacji zasięgu rażenia ataków sieciowych — tj. ograniczenia liczby zasobów, do których atakujący może uzyskać dostęp po przełamaniu pierwszej linii obrony.

Proponowane podejście opiera się na trzech komponentach. Pierwszy to budowa grafu ataku na podstawie topologii sieci i danych o podatnościach (CVE/NVD), gdzie węzły reprezentują pary host-usługa, a krawędzie — możliwe ścieżki eksploitacji z przypisanymi prawdopodobieństwami wynikającymi z metryk CVSS. Drugi komponent to symulacja Monte Carlo propagacji atakującego po grafie, generująca mapę zasięgu rażenia dla każdego punktu wejścia. Trzeci to algorytmy optymalizacji obrony: segmentacja sieci (min-cut) i priorytetyzacja łatania podatności (algorytm zachłanny oparty na redukcji zasięgu rażenia).

Ewaluacja zostanie przeprowadzona na syntetycznych, ale realistycznych topologiach sieciowych o różnej skali (20–1000 hostów). Proponowane podejście zostanie porównane z trzema bazami odniesienia: priorytetyzacją opartą na CVSS, losowym doborem działań obronnych oraz brakiem obrony. Analiza statystyczna wyników symulacji (test Manna-Whitneya) pozwoli określić istotność różnic między strategiami.

Narzędzie badawcze zostanie zaimplementowane w Elixir (silnik symulacji) z wizualizacją w Phoenix LiveView.
