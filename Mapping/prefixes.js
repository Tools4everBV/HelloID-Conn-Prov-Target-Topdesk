function getPrefixes() {
    let middleName = Person.Name.FamilyNamePrefix;
    let middleNamePartner = Person.Name.FamilyNamePartnerPrefix;
    let convention = Person.Name.Convention;
    
    let nameFormatted = '';
    let prefix = '';

    switch (convention) {
        case "B":
            nameFormatted = middleName;
            break;
        case "BP":
            nameFormatted = middleName;
            break;
        case "P":
            nameFormatted = middleNamePartner;
            break;
        case "PB":
            nameFormatted = middleNamePartner;
            break;
        default:
            nameFormatted = middleName;
            break;
    }

    if (typeof nameFormatted !== 'undefined' && nameFormatted) {
        prefix = nameFormatted.trim();
    } else {
        prefix = nameFormatted;
    }

    return prefix;
}

getPrefixes();