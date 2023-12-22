function getValue() {
    let initials = Person.Name.Initials;
    if ((initials.length) > 10) {
        initials = initials.substring(0, 10)
    }
    return initials;
}

getValue();