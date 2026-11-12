# Tableau de bord — appli iPad mini 4 (iPadOS 15)

Même interface que la version Android (le `index.html` de la branche), dans une appli iOS (WKWebView) qui fournit le pont `window.Native` : réseau (Airzone en HTTP local, météo, GitHub, Tuya), réglages, batterie, veille, Bluetooth (lumière LED).

**État : appli 0.1 — compile sur GitHub Actions (Xcode 26, cible iPadOS 15.0). Pas encore essayée sur un vrai iPad.**
Faits : étapes 1 (coque), 2 (HTTP + réglages), 3 (Bluetooth). Pas faits : étape 4 (mises à jour signées de l'interface), étape 5 (signature automatisée).

## Récupérer l'appli
1. GitHub > dépôt `dash-mini-4` > onglet **Actions** > dernier passage de « iPad (IPA non signé) » (branche `test`).
2. En bas de la page, section **Artifacts** : télécharger `TableauDeBord-iPad-unsigned-ipa` (zip contenant `TableauDeBord-iPad-unsigned.ipa`).

L'IPA n'est **pas signé** : il faut le signer avec ton identifiant Apple au moment de l'installer.

## Installer sur l'iPad (depuis ton PC Windows)
- Outil : **Sideloadly** (ou AltStore). Installer d'abord iTunes et iCloud depuis le site d'Apple (pas le Microsoft Store).
- Brancher l'iPad en USB, déverrouillé, « Faire confiance » à l'ordinateur.
- Glisser l'IPA dans Sideloadly, saisir l'identifiant Apple, Start.
- Sur l'iPad : Réglages > Général > Gestion des appareils (VPN et gestion de l'appareil) > ton identifiant > **Faire confiance**. (Pas de « Mode développeur » à activer sur iPadOS 15 : il n'existe que depuis iPadOS 16.)
- Compte Apple **gratuit** : l'appli expire au bout de **7 jours** (il faut la ré-installer ou la rafraîchir, 3 applis maximum). Compte développeur payant : 1 an.
- Conseil : utiliser un identifiant Apple dédié à ça.

## Premier lancement
- Accepter **Bluetooth** et **Réseau local** (sans « Réseau local », la clim Airzone reste injoignable).
- Autre > Réglages : adresse Airzone (`ip:port`), latitude/longitude, jeton de diagnostic, etc. — comme sur Android.
- Lumière LED : sur iOS il n'y a pas d'adresse MAC. Laisser le champ **vide** (ou garder l'ancienne adresse) : l'appli cherche un appareil nommé BLEDOM / ELK / LEDBLE, ou exposant le service FFF0, et mémorise son identifiant. Si plusieurs lumières voisines posent problème : saisir un bout du nom, ou l'identifiant iOS.
- Agenda / Tuya : déposer `ical.txt` et `tuya.txt` dans le dossier de l'appli (app Fichiers > Sur mon iPad > Tableau de bord), puis Autre > Réglages > **Importer**.

## Différences avec Android
- Pas d'économie d'énergie automatique ni de mode « Accès guidé » depuis l'appli : iOS ne le permet pas (Accès guidé : triple clic sur le bouton principal, à faire à la main). La veille met la luminosité au minimum et l'écran reste allumé.
- Pas d'installation d'APK ; mises à jour de l'interface : étape 4 (la page affiche un refus tant que ce n'est pas fait). En attendant, l'interface est celle compilée dans l'appli : pour la mettre à jour, relancer le workflow (Actions > Run workflow) et ré-installer.
- Open-Meteo est d'abord essayé en HTTP (astuce Android 4.4) : iOS le refuse, la page retombe aussitôt sur HTTPS. Sans conséquence.

## Compiler
Rien à faire à la main : le workflow `.github/workflows/ios.yml` copie `index.html`, génère le projet avec XcodeGen (`ios/project.yml`), compile sans signature et publie l'IPA.
