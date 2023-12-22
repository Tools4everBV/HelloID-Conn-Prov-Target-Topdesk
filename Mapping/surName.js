// Please enter the mapping logic to generate the Lastname.
function generateLastName() {
    let middleName = Person.Name.FamilyNamePrefix;
    let lastName = Person.Name.FamilyName;
    let middleNamePartner = Person.Name.FamilyNamePartnerPrefix;
    let lastNamePartner = Person.Name.FamilyNamePartner;
    let convention = Person.Name.Convention;

    let nameFormatted = '';

    switch (convention) {
        case "B":
            nameFormatted = lastName;
            break;
        case "BP":
            nameFormatted = lastName;
            nameFormatted = nameFormatted + ' - ';
            if (typeof middleNamePartner !== 'undefined' && middleNamePartner) { nameFormatted = nameFormatted + middleNamePartner + ' ' }
            nameFormatted = nameFormatted + lastNamePartner;
            break;
        case "P":
            nameFormatted = lastNamePartner;
            break;
        case "PB":
            nameFormatted = lastNamePartner;
            nameFormatted = nameFormatted + ' - ';
            if (typeof middleName !== 'undefined' && middleName) { nameFormatted = nameFormatted + middleName + ' ' }
            nameFormatted = nameFormatted + lastName;
            break;
        default:
            nameFormatted = lastName;
            break;
    }

    if (typeof nameFormatted !== 'undefined' && nameFormatted) {
        lastName = nameFormatted.trim();
    } else {
        lastName = nameFormatted;
    }
    
    return lastName;
}

generateLastName();