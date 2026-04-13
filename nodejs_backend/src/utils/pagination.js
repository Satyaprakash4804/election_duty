'use strict';

const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 200;

function pageParams(query) {
  const page = Math.max(1, parseInt(query.page, 10) || 1);
  const limit = Math.min(MAX_PAGE_SIZE, Math.max(1, parseInt(query.limit, 10) || DEFAULT_PAGE_SIZE));
  const offset = (page - 1) * limit;
  return { page, limit, offset };
}

function paginated(res, data, total, page, limit) {
  return res.json({
    status: 'success',
    message: 'success',
    data: {
      data,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    },
  });
}

module.exports = { pageParams, paginated, DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE };
