function getValue() {
    let gender = Person.Details.Gender;
    let outputGender = ''
    switch (gender) {
        case "M":
            outputGender = 'MALE'
            break;
        case "V":
            outputGender = 'FEMALE'
            break;
        default:
            outputGender = 'UNDEFINED'
            break;
    }
    return outputGender;
}

getValue();