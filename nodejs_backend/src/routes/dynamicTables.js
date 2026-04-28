'use strict';

const express = require('express');
const router = express.Router();

const DynamicTable = require('../models/DynamicTable');
const DynamicRow = require('../models/DynamicRow');
const { ok, err, adminRequired } = require('../middleware/auth');
const { getPool } = require('../config/db');

// ── Helper: get user district from MySQL ──────────────────────────────────────
async function getUserDistrict(userId) {
  const pool = await getPool();
  const [rows] = await pool.execute(
    "SELECT district FROM users WHERE id=?",
    [userId]
  );
  return rows[0]?.district || '';
}

// ─────────────────────────────────────────────────────────────────────────────
// GET ALL TABLES  (pagination + search)
// ─────────────────────────────────────────────────────────────────────────────
router.get('/', adminRequired, async (req, res) => {
  try {
    const { page = 1, limit = 12, search = '' } = req.query;
    const district = await getUserDistrict(req.user.id);

    const query = {
      district,
      table_name: { $regex: search, $options: 'i' },
    };

    const [tables, total] = await Promise.all([
      DynamicTable.find(query)
        .skip((page - 1) * Number(limit))
        .limit(Number(limit))
        .sort({ createdAt: -1 }),
      DynamicTable.countDocuments(query),
    ]);

    return ok(res, { tables, total });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET SINGLE TABLE  (columns + rows, paginated + searchable)
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:name', adminRequired, async (req, res) => {
  try {
    const { name } = req.params;
    const { page = 1, limit = 50, search = '' } = req.query;
    const district = await getUserDistrict(req.user.id);

    const table = await DynamicTable.findOne({ table_name: name, district });
    if (!table) return err(res, 'Table not found', 404);

    // Search across all row data fields using a flexible regex on stringified data
    const rowQuery = search
      ? {
          table_id: table._id,
          $or: table.columns.map(c => ({
            [`data.${c.key}`]: { $regex: search, $options: 'i' },
          })),
        }
      : { table_id: table._id };

    const [rows, total] = await Promise.all([
      DynamicRow.find(rowQuery)
        .skip((page - 1) * Number(limit))
        .limit(Number(limit))
        .sort({ createdAt: -1 }),
      DynamicRow.countDocuments(rowQuery),
    ]);

    return ok(res, { table, rows, total });
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// CREATE TABLE
// ─────────────────────────────────────────────────────────────────────────────
router.post('/', adminRequired, async (req, res) => {
  try {
    const { table_name, columns = [] } = req.body;
    if (!table_name) return err(res, 'table_name required');

    const district = await getUserDistrict(req.user.id);

    const existing = await DynamicTable.findOne({ table_name, district });
    if (existing) return err(res, 'A table with this name already exists', 409);

    const table = await DynamicTable.create({
      table_name,
      columns,
      created_by: req.user.id,
      district,
    });

    return ok(res, table, 'Table created');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE TABLE  ← was missing
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/:id', adminRequired, async (req, res) => {
  try {
    const { id } = req.params;
    const district = await getUserDistrict(req.user.id);

    const table = await DynamicTable.findOne({ _id: id, district });
    if (!table) return err(res, 'Table not found', 404);

    // Delete all rows belonging to this table
    await DynamicRow.deleteMany({ table_id: id });
    await DynamicTable.findByIdAndDelete(id);

    return ok(res, null, 'Table deleted');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// ADD COLUMN  ← was missing
// ─────────────────────────────────────────────────────────────────────────────
router.post('/:id/columns', adminRequired, async (req, res) => {
  try {
    const { id } = req.params;
    const { key, label, type = 'text' } = req.body;

    if (!key || !label) return err(res, 'key and label required');

    const district = await getUserDistrict(req.user.id);
    const table = await DynamicTable.findOne({ _id: id, district });
    if (!table) return err(res, 'Table not found', 404);

    // Check key uniqueness
    if (table.columns.some(c => c.key === key)) {
      return err(res, `Column key "${key}" already exists`, 409);
    }

    await DynamicTable.updateOne(
      { _id: id },
      { $push: { columns: { key, label, type } } }
    );

    return ok(res, null, 'Column added');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// RENAME / EDIT COLUMN LABEL  ← was missing
// ─────────────────────────────────────────────────────────────────────────────
router.patch('/:id/columns/:key', adminRequired, async (req, res) => {
  try {
    const { id, key } = req.params;
    const { label } = req.body;

    if (!label) return err(res, 'label required');

    const district = await getUserDistrict(req.user.id);
    const table = await DynamicTable.findOne({ _id: id, district });
    if (!table) return err(res, 'Table not found', 404);

    const colIndex = table.columns.findIndex(c => c.key === key);
    if (colIndex === -1) return err(res, 'Column not found', 404);

    await DynamicTable.updateOne(
      { _id: id, 'columns.key': key },
      { $set: { 'columns.$.label': label } }
    );

    return ok(res, null, 'Column updated');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE COLUMN  (remove from schema + unset in all rows)
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/:id/columns/:key', adminRequired, async (req, res) => {
  try {
    const { id, key } = req.params;
    const district = await getUserDistrict(req.user.id);

    const table = await DynamicTable.findOne({ _id: id, district });
    if (!table) return err(res, 'Table not found', 404);

    await Promise.all([
      DynamicTable.updateOne({ _id: id }, { $pull: { columns: { key } } }),
      DynamicRow.updateMany({ table_id: id }, { $unset: { [`data.${key}`]: '' } }),
    ]);

    return ok(res, null, 'Column deleted');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// ADD ROW
// ─────────────────────────────────────────────────────────────────────────────
router.post('/:id/rows', adminRequired, async (req, res) => {
  try {
    const row = await DynamicRow.create({
      table_id: req.params.id,
      data: req.body.data || {},
    });
    return ok(res, row, 'Row added');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// UPDATE ROW
// ─────────────────────────────────────────────────────────────────────────────
router.put('/rows/:rowId', adminRequired, async (req, res) => {
  try {
    const row = await DynamicRow.findByIdAndUpdate(
      req.params.rowId,
      { data: req.body.data },
      { new: true }
    );
    if (!row) return err(res, 'Row not found', 404);
    return ok(res, row, 'Row updated');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE ROW
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/rows/:rowId', adminRequired, async (req, res) => {
  try {
    const row = await DynamicRow.findByIdAndDelete(req.params.rowId);
    if (!row) return err(res, 'Row not found', 404);
    return ok(res, null, 'Row deleted');
  } catch (e) {
    return err(res, e.message, 500);
  }
});

module.exports = router;