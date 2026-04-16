import axios from 'axios';

const BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:5000/api';

export const apiClient = axios.create({
  baseURL: BASE_URL,
  timeout: 20000,
  withCredentials: true,
  headers: { 'Content-Type': 'application/json' },
});

// Request interceptor — attach token if present
apiClient.interceptors.request.use((config) => {
  const token = localStorage.getItem('AUTH_TOKEN');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// Response interceptor — handle 401 globally
apiClient.interceptors.response.use(
  (res) => res.data,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.clear();
      sessionStorage.clear();
      window.location.href = '/login';
    }
    const msg =
      error.response?.data?.message ||
      error.response?.data?.error ||
      error.message ||
      'An error occurred';
    return Promise.reject(new Error(msg));
  }
);

export default apiClient;
