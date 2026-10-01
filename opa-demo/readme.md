# Basic OPA/Gateway setup

## Context

Bij BRP-koppelingen wordt het ophaalpunt niet alleen meegegeven in de URL, zoals je bij een API zou verwachten, maar ook in de requestbody. Bijvoorbeeld:

```http
{{baseUrl}}brp/personen
```

```json
{
  "type": "ZoekMetPostcodeEnHuisnummer",
  "postcode": "1234AB",
  "huisnummer": "1",
  "fields": ["burgerservicenummer", "naam", "geboorte", "adressering"]
}
```

Het veld `type` bepaalt hoe de gegevens worden opgehaald. Het veld `fields` geeft aan welke gegevens worden teruggegeven.

## Waarom OPA?

Om te voorkomen dat elke applicatie die via onze gateway de BRP-API aanroept zomaar alle gegevens kan ophalen, wordt vaak een PDP (Policy Decision Point) gebruikt. De gateway stuurt de requestgegevens naar dit beslispunt.

In dit project wordt de requestbody doorgestuurd. De policy in `field-policy.rego` leest de body uit en vergelijkt `fields` met `allowed_fields` in `data.json`.

De logica en de toegestane gegevens zijn bewust gescheiden. Zo kunnen beheerders eenvoudig een veld toevoegen. In de praktijk kan `data.json` worden vervangen door een database of een andere opslagvoorziening. 

Voor core: data.json is genoeg, een database valt buiten de scope van de portal.

## Meerdere policies

Het is mogelijk om meerdere Rego-bestanden in een OPA-container te plaatsen. OPA onderscheidt deze op basis van de package die bovenaan elk bestand is gedefinieerd. De twee Rego-bestanden in dit project zijn bereikbaar via:

- `localhost:8181/v1/data/apisix/authz/v1`
- `localhost:8181/v1/data/apisix/authz/v2`

## Besluiten loggen

Ook `opa-config.yaml` is van belang. In dit voorbeeld is het loggen van besluiten ingeschakeld. Deze logs kunnen worden gebruikt voor protocollering.