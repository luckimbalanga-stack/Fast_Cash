# Fast-Cash

Votre argent, votre monnaie, à proximité.

Ces trois comptes servent à la mise en service. Ils peuvent être supprimés ensuite.

## Client

Connexion mobile, avec le numéro et le code de vérification.

| | |
|---|---|
| Nom | Jean Mwamba |
| Numéro | +243 810 123 456 |
| Réseau | Orange Money |

## PDR (point de retrait)

Même écran « Se connecter » que le client. Si le numéro appartient à un PDR :
1. **Mot de passe** du point
2. **OTP** de confirmation (simulé à l’écran / logs tant que le SMS n’est pas branché)

Le mot de passe est défini à la **création du PDR** dans l’admin web. Un admin peut le **réinitialiser** depuis la fiche du point : le nouveau mot de passe s’affiche à l’écran (envoi SMS à brancher plus tard).

| | |
|---|---|
| Point | PDR Gombe Centre |
| Code | FC-PDR-001 |
| Responsable | Aline Mputu |
| Numéro | +243 815 000 001 |
| Mot de passe | PdrGombe-2026 |
| Adresse | 12 Avenue du Commerce, Gombe, Kinshasa |

## Administration web

Connexion par e-mail et mot de passe.

| | |
|---|---|
| Nom | Admin Fast-Cash |
| E-mail | admin@fastcash.cd |
| Mot de passe | FastCash-2026 |
| Rôle | Super administrateur |

La passerelle SMS n’est pas branchée. Pour les **clients**, le code OTP s’affiche à l’écran et dans la console du serveur (valable cinq minutes). Pour les **PDR**, la connexion utilise uniquement le mot de passe.

## Déploiement

Guide complet (Render + Android, checklist, dépannage) : **[DEPLOY_RENDER.md](DEPLOY_RENDER.md)**.
