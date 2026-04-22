'use strict';

const mongoose = require('mongoose');

const columnSchema = new mongoose.Schema({
  key: { type: String, required: true },
  label: { type: String, required: true },
  type: { type: String, default: 'text' },
}, { _id: false });

const dynamicTableSchema = new mongoose.Schema({
  table_name: { type: String, required: true, unique: true, index: true },
  columns: [columnSchema],

  created_by: { type: Number, required: true }, // MySQL user id
  district: { type: String, index: true },

}, { timestamps: true });

dynamicTableSchema.index({ district: 1, table_name: 1 });
dynamicTableSchema.index({ created_by: 1 });

module.exports = mongoose.model('DynamicTable', dynamicTableSchema);