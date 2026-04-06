import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import { AuthProvider } from './context/AuthContext'
import { ProtectedRoute, PublicRoute } from './components/ProtectedRoute'

import LoginPage from './pages/LoginPage'
import AdminDashboard from './pages/admin/AdminDashboard'
import SuperDashboard from './pages/super/SuperDashboard'
import MasterDashboard from './pages/master/MasterDashboard'
import StaffDutyPage from './pages/StaffDutyPage'

import { useEffect } from "react"
import { messaging } from "./firebase"
import { getToken, onMessage } from "firebase/messaging"

export default function App() {

  useEffect(() => {
    // 🔔 Ask permission
    Notification.requestPermission().then((permission) => {
      console.log("Permission:", permission)

      if (permission === "granted") {
        getToken(messaging, {
          vapidKey: "BASHDZdHH26dxoAX8ElgJCptf5l5_JVGnBqKnQUnq7kiAjkWz9HuNu41r3fole4QAfe6y7Jd6Fs8UyvKnDUHybQ",
        })
          .then((currentToken) => {
            if (currentToken) {
              console.log("✅ FCM Token:", currentToken)

              // Send token to backend
              fetch("http://localhost:5000/save-token", {
                method: "POST",
                headers: {
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({
                  token: currentToken,
                  platform: "react",
                }),
              })
            } else {
              console.log("❌ No token received")
            }
          })
          .catch((err) => {
            console.log("❌ Token error:", err)
          })
      } else {
        console.log("❌ Notification permission denied")
      }
    })

    // 🔔 Foreground messages
    onMessage(messaging, (payload) => {
      console.log("📩 Message received:", payload)

      alert(
        payload.notification?.title + "\n" +
        payload.notification?.body
      )
    })
  }, [])

  return (
    <AuthProvider>
      <BrowserRouter>

        <Toaster position="top-right" />

        <Routes>
          <Route path="/login" element={
            <PublicRoute>
              <LoginPage />
            </PublicRoute>
          } />

          <Route path="/admin/*" element={
            <ProtectedRoute allowedRoles={['ADMIN']}>
              <AdminDashboard />
            </ProtectedRoute>
          } />

          <Route path="/super/*" element={
            <ProtectedRoute allowedRoles={['SUPER_ADMIN']}>
              <SuperDashboard />
            </ProtectedRoute>
          } />

          <Route path="/master/*" element={
            <ProtectedRoute allowedRoles={['MASTER', 'ADMIN']}>
              <MasterDashboard />
            </ProtectedRoute>
          } />

          <Route path="/staff" element={
            <ProtectedRoute allowedRoles={['STAFF']}>
              <StaffDutyPage />
            </ProtectedRoute>
          } />

          <Route path="/" element={<Navigate to="/login" replace />} />
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>

      </BrowserRouter>
    </AuthProvider>
  )
}