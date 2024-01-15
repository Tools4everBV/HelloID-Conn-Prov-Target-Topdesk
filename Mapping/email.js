function getEmail() {
    let mail = '';

    if (typeof Person.Accounts.MicrosoftActiveDirectory.mail !== 'undefined' && Person.Accounts.MicrosoftActiveDirectory.mail) {
        mail = Person.Accounts.MicrosoftActiveDirectory.mail;
    }

    return mail;
}

getEmail()