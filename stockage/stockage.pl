#!/usr/bin/perl -w
require maxhtmlparsing;
require maxindexing;
use strict;
use open qw/:std :utf8/;
use MongoDB;
use Encode;

my @motsVides = separer(lireTexte('motsVides'));

######################
### Initialisation ###
######################

# On se connecte à la base de données
my $client = MongoDB::MongoClient -> new;
my $db = $client -> get_database('Wikinews');
# On se connecte à l'index direct et à l'index inversé
my $inverse = $db -> get_collection('Index inverse');
my $direct = $db -> get_collection('Index direct');
# On les vide
$inverse -> remove();
$direct -> remove();
# On instancie un index direct et un un index inverse
my %indexDirect = ();
my %indexInverse = ();

# On vide le blob contenant tous les mots (ou pas!)
open my $blob, '>', 'blob' or die $!;
print {$blob} '';

#################################
### Parsage des fichiers HTML ###
#################################

# On récupère les fichiers HTML dans le dossier data
opendir (DIR, 'data/') or die $!;
# On regarde chaque fichier HTML
while (my $fichier = readdir(DIR)) {
	# On vérifie que c'est bien un fichier HTML 
	if ($fichier =~ /(.*)\.html/) {
		# On récupère le nom du document (sans le ".html")
		my $nom = Encode::decode('utf8', $1);
		
		# Les apostrophes sont des PITA
		#$nom =~ s/'/ /g;

		# On remplace les espaces en trop
		$nom =~ s/\s+/ /g;
		# On ouvre le fichier
		open FILE, '<', "data/$fichier" or die $!;
		# On met chaque ligne dans un tableau
		my @data = <FILE>;
		# On joint les lignes et on enlève les espaces en trop
		my $contenu = maxhtmlparsing::clean(@data);
		# On cherche la dernière date de modification de l'article
		$indexDirect{$nom}{'dateModification'} = maxhtmlparsing::dateModification($contenu);
		# On cherche les catégories de l'article
		$indexDirect{$nom}{'categories'} = [maxhtmlparsing::categories($contenu)];
		# On cherche les sources de l'article
		$indexDirect{$nom}{'sources'} = [maxhtmlparsing::sources($contenu)];
		# On récupère le body
		my $body = maxhtmlparsing::body($contenu);
		# On enlève les liens vers les réseaux sociaux
		$body = maxhtmlparsing::enleverPartage($body);
		# On enlève la deuxième date de l'article (redondance)
		$body = maxhtmlparsing::enleverEvenement($body);
		# On récupère les paragraphes entre les balises p
		$body = maxhtmlparsing::paragraphes($body);
		# On enlève le code HTML
		$body = maxhtmlparsing::retirerHTML($body);
		# On récupère la date d'écriture de l'article
		$indexDirect{$nom}{'dateEcriture'} = maxhtmlparsing::date($body);
		# On sauvegarde le body dans un dossier
		open my $fichierTexte, '>:encoding(UTF-8)', 'bodies/'.$nom.'.txt' or die $!;
		print {$fichierTexte} $body;
	}
}

######################################
### Indexation des fichiers textes ###
######################################

# On index les bodys extraits
indexerCollection('bodies/');

#####################################
### Stockage dans la base MongoDB ###
#####################################

# On stocke l'index direct
foreach my $document (keys %indexDirect) {
	$direct -> save({
		'_id' => $document,
		'dateModification' => $indexDirect{$document}{'dateModification'},
		'categories' => $indexDirect{$document}{'categories'},
		'sources' => $indexDirect{$document}{'sources'},
		'dateEcriture' => $indexDirect{$document}{'dateEcriture'},
		'nbMots' => $indexDirect{$document}{'nbMots'},
		'longueur' => $indexDirect{$document}{'longueur'},
		'mots' => $indexDirect{$document}{'mots'},
		'notes' => [],
		'commentaires' => []
		});
}

# On stocke l'index inverse
foreach my $mot (keys %indexInverse) {
	$inverse -> save({
		'_id' => $mot,
		'nbDocuments' => $indexInverse{$mot}{'nbDocuments'},
		'documents' => $indexInverse{$mot}{'documents'}
		});
}

##########################################################
### Les fonctions suivantes ne sont pas dans un module ###
### car elles nécessitent des variables globales.      ###
##########################################################

sub indexer {
	# Paramètres
	my ($idDoc, $chemin) = @_;

	# Les apostrophes sont des PITA
	#$idDoc =~ s/'/ /g;

	# On remplace les espaces en trop
	$idDoc =~ s/\s+/ /g;
	# On prend le contenu du document
	my $mots = lireTexte($chemin);
	# On lui ajoute les mots du titre
	$mots .= $idDoc;
	# On le nettoie
	$mots = minuscules($mots);
	$mots = ponctuation($mots);
	foreach my $mot (@motsVides) {
		$mots =~ s/\b$mot\b/ /gi;
		$mots =~ s/\s+/ /g;
	}
	# On ajoute les mots à un "blob" qui contient tous les mots pour des analyses futures
	open my $blob, '>>', 'blob' or die $!;
	print {$blob} "$mots";
	
	my @mots = lemmatisation($mots);
	# On cherche la frequence des mots
	my %frequence = frequence(@mots);
	# Index direct
	foreach my $terme ( keys %frequence ) {
		my $frequenceMot = $frequence{$terme};
		$indexDirect{$idDoc}{'mots'}{$terme} = $frequenceMot;
		$indexDirect{$idDoc}{'nbMots'} += 1;
		$indexDirect{$idDoc}{'longueur'} += $frequenceMot;
	}
	# Index inverse
	foreach my $terme ( keys %frequence ) {
		$indexInverse{$terme}{'documents'}{$idDoc} = $frequence{$terme};
		$indexInverse{$terme}{'nbDocuments'} += 1;
	}
}
sub indexerCollection {
	# Paramètres
	my ($chemin) = @_;
	# On récupère les fichiers
	my @fichiers = lister($chemin);
	# On parcourt chaque fichier
	foreach my $fichier (@fichiers) {
		$fichier =~ /.+\/+(.+).txt/;
		my $nom = Encode::decode('utf8', $1);
		indexer($nom, $fichier);
	}
}
