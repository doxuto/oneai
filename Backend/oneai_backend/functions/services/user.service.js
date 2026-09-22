const { db } = require('../config/config-firebase');

const collectionName = "users";

exports.getUserByEmail = async(email) => {
    const collection = await db.collection(collectionName);
    const data = await collection.where('email', '==', email).get();
    const result = data.docs.map(doc => doc.data());
    return result;
}

exports.getUserByEmail = async(email) => {
    let userResult = await db.collection(collectionName).where('email', '==', email).get();
    if(userResult.empty) {
        await db.collection(collectionName).add({
            email: email,
        });
        userResult = await db.collection(collectionName).where('email', '==', email).get();
    }
    let userInfo = {};
    if(userResult.docs.length >= 1) {
        userInfo = userResult.docs[0].data();
    }
    return userInfo;
}

exports.addChatToMinutes = async(email, type, message) => {
    let userResult = await db.collection(collectionName).where('email', '==', email).get();
    const userInfo = userResult.docs[0].data();
    if(!userInfo.minutes) {
        userInfo.minutes = [];
    }
    const newRecord = {
        type: type,
        message: message,
        time: new Date().toISOString(),
    };
    userInfo.minutes.push(newRecord);

    await db.collection(collectionName).doc(userResult.docs[0].id).set(userInfo);
    return newRecord;
}