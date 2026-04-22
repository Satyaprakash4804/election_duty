'use strict';

const mongoose = require('mongoose');

const dynamicRowSchema = new mongoose.Schema({
  table_id: { type: mongoose.Schema.Types.ObjectId, ref: 'DynamicTable', index: true },
  data: { type: Object, default: {} }
}, { timestamps: true });

dynamicRowSchema.index({ table_id: 1, createdAt: -1 });

module.exports = mongoose.model('DynamicRow', dynamicRowSchema);