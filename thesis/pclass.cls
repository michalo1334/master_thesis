\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{pclass}[2020/15/05 Praca Inzynierska - Krystian Lapa]
\LoadClass[12pt, openany]{book}

\usepackage[a4paper, left=35mm, top=20mm, bottom=20mm, right=20mm]{geometry}
\usepackage{mathptmx}
\usepackage[T1]{fontenc}
\usepackage[newfloat]{minted}
\usepackage{caption}
\usepackage{svg}
\usepackage{emptypage}
\usepackage{fancyhdr}
\usepackage{csquotes}
\usepackage{siunitx}
\usepackage{tikz}
\usepackage{array}
\usepackage{multirow}
\usepackage{fontspec}
\setmonofont{DejaVu Sans Mono}
\usepackage{newunicodechar}
\newfontface{\whatever}{DejaVu Sans}
\newunicodechar{⌇}{{\whatever{⌇}}}
\newunicodechar{∫}{{\whatever{∫}}}
\newunicodechar{∪}{{\whatever{∪}}}
\newunicodechar{∀}{{\whatever{∀}}}
\newunicodechar{↞}{{\whatever{↞}}}
\usepackage{epigraph}
\usepackage[most]{tcolorbox}
\usepackage{microtype}
\usepackage{booktabs}
\usepackage{enumitem}
\usepackage{mathtools}
\usepackage{amsfonts}
\usepackage{hyperref}
\hypersetup{
	colorlinks=true,
	linkcolor=black,
	citecolor=black,
	urlcolor=black,
}
\usepackage{cleveref}
\usepackage[backend=biber, style=numeric]{biblatex}

\renewcommand{\baselinestretch}{1.25}
\def\@dotsep{4.5}
\providecommand*{\listoflistingsname}{List of Listings}

\newenvironment{code}{\captionsetup{type=listing}}{}
\SetupFloatingEnvironment{listing}{name=Source Code}

\graphicspath{{img/}}
\svgpath{{img/}}

\newtcblisting{tcbcode}[2][]{
	listing engine=minted,
	minted language=#2,
	minted options={breaklines, fontsize=\footnotesize, #1},
	breakable,
	colback=white,
	colframe=black!60,
	listing only,
	enhanced,
	left=6pt, right=6pt, top=6pt, bottom=6pt,
	boxrule=0.4pt,
}

\newcommand{\typpracy}[1]{\newcommand{\@typpracy}{#1}}
\newcommand{\tieng}[1]{\newcommand{\@tieng}{#1}}
\newcommand{\album}[1]{\newcommand{\@album}{#1}}
\newcommand{\studia}[1]{\newcommand{\@studia}{#1}}
\newcommand{\poziom}[1]{\newcommand{\@poziom}{#1}}
\newcommand{\promotor}[1]{\newcommand{\@promotor}{#1}}
\newcommand{\dedykacja}[1]{\newcommand{\@dedykacja}{#1}}
\newcommand{\epigrafquote}[1]{\newcommand{\@epigrafquote}{#1}}
\newcommand{\epigrafsource}[1]{\newcommand{\@epigrafsource}{#1}}

\newcommand{\displayepigraph}{
	\ifdefined\@epigrafquote
		\ifx\@epigrafquote\empty
		\else
			{\clearpage
				\thispagestyle{empty}
				\centering
				\vspace{3pt}
				\section*{Epigraph}
				\itshape
				\epigraph{\@epigrafquote}{\@epigrafsource}
			}
			{\par
				\vspace{\stretch{3}}
			}
		\fi
	\fi
}

\fancyhf{}
\renewcommand{\headrulewidth}{0pt}
\fancyfoot[LE,RO]{\thepage}
\pagestyle{fancy}
\fancypagestyle{plain}{
	\fancyhf{}
	\renewcommand{\headrulewidth}{0pt}
	\fancyhf[lef,rof]{\thepage}
}

\newcommand{\frontpage} {
	\thispagestyle{empty}
	\begin{center}
		
		\includegraphics[scale=1]{img/logo_wiisi.png} \\
		\vspace{75pt}
		{\LARGE\@typpracy} \\
		\vspace{60pt}
		{\Large\bf\@title} \\
		\vspace{16pt}
		{\Large\@tieng} \\
		\vspace{32pt}
	\end{center} 
	{\hfill\begin{tabular}{l}
		{\large\@author} \\
		Nr albumu: \@album\\
		Kierunek: Informatyka \\
		Studia: \@studia\\
		Poziom studiów: \@poziom \\
		{\large Promotor pracy:} \\
		\@promotor
	\end{tabular}} \\
    \vspace*{\fill}
	Praca przyjęta dnia: \vspace{1ex}\\
	Podpis promotora: \\
	\begin{center}
		\textit{Częstochowa}, \the\year{}
	\end{center}
	\ifdefined\@dedykacja
		\cleardoublepage
		\thispagestyle{empty}
		\vspace*{\fill}
		{\hfill\begin{tabular}{l}
			\@dedykacja
		\end{tabular}}
	\fi
	\cleardoublepage
	\displayepigraph
	\pagenumbering{arabic}
}

\newcommand{\oswiadczenie} {
	\cleardoublepage
	\pagestyle{empty}
	{\noindent \bf Politechnika Częstochowska\\Wydział Informatyki i Sztucznej Inteligencji}\\\\
	Imię i nazwisko: \@author \hfill Częstochowa, dn. ............\\
	Nr albumu: \@album\\
	Kierunek: Informatyka\\
	Wydział: Informatyki i Sztucznej Inteligencji\\
	Politechnika Częstochowska\\
	\vspace{32pt}
	\begin{center}
		\bf OŚWIADCZENIE\\autora pracy dyplomowej*
	\end{center}
    Pod rygorem odpowiedzialności karnej oświadczam, że złożona przeze mnie praca dyplomowa pt. „\@title” jest moim samodzielnym opracowaniem i nie zawiera treści uzyskanych w sposób niezgodny z obowiązującymi przepisami. \\
    Jednocześnie oświadczam, że praca w całości lub we fragmentach nie była wcześniej przedmiotem procedur związanych z uzyskaniem tytułu zawodowego w uczelni. \\
    Wyrażam / nie wyrażam ** zgodę na nieodpłatne wykorzystanie przez Politechnikę Częstochowską całości lub fragmentów ww. pracy w publikacjach Politechniki Częstochowskiej.
    Ponadto oświadczam, że treść pracy przedstawionej przeze mnie do obrony zawarta na przekazywanym nośniku elektronicznym jest identyczna z wersją drukowaną. \\
    \vspace{64pt} \\
        
    {\hfill\begin{tabular}{c}
    		................................................................. \\
    		\small podpis studenta
    \end{tabular}} \\
	\vfill
	\noindent \scriptsize * w przypadku zbiorowej pracy dyplomowej, dołącza się oświadczenia każdego ze współautorów pracy dyplomowej \\
	*** niepotrzebne skreślić
}
