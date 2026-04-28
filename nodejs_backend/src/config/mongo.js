'use strict';

const mongoose = require('mongoose');

let isConnected = false;

async function connectMongo() {
    if (isConnected) {
        return mongoose.connection;
    }

    try {
        const uri = process.env.MONGO_URI;

        if (!uri) {
            throw new Error('MONGO_URI not found in env');
        }

        const conn = await mongoose.connect(uri);

        isConnected = true;

        console.log(`🍃 MongoDB connected: ${conn.connection.host}`);

        return conn;
    } catch (err) {
        console.error('❌ MongoDB connection failed:', err.message);
        process.exit(1);
    }
}

module.exports = { connectMongo };