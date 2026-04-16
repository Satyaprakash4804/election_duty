import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { authApi } from '../api/endpoints';

export const useAuthStore = create(
  persist(
    (set, get) => ({
      user: null,
      token: null,
      role: null,
      isAuthenticated: false,

      login: async (pno, password) => {
        const res = await authApi.login(pno, password);
        const data = res.data;
        const user = data.user;
        const token = data.token || null;

        if (token) localStorage.setItem('AUTH_TOKEN', token);

        set({
          user,
          token,
          role: user.role?.toUpperCase(),
          isAuthenticated: true,
        });
        return user.role?.toUpperCase();
      },

      logout: async () => {
        try { await authApi.logout(); } catch (_) {}
        localStorage.removeItem('AUTH_TOKEN');
        set({ user: null, token: null, role: null, isAuthenticated: false });
      },

      setUser: (user) => set({ user }),
    }),
    {
      name: 'auth-store',
      partialize: (s) => ({
        user: s.user,
        token: s.token,
        role: s.role,
        isAuthenticated: s.isAuthenticated,
      }),
    }
  )
);
