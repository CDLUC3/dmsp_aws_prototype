import React from "react";
import { createBrowserRouter, RouterProvider } from "react-router-dom";

import Home from "./pages/home/home";
import Landing from "./pages/landing/landing";
import Dashboard from "./pages/dashboard/dashboard";
import { Authenticate, Logout, Unauthorized } from "./Auth";

import PageNotFound from "./pages/not_found/not_found";

const router = createBrowserRouter([
  {
    path: "/dmps/*",
    element: <Landing />,
  },
  {
    path: "/unauthorized",
    element: <Unauthorized />,
  },
  {
    path: "/authenticate",
    element: <Authenticate />,
  },
  {
    path: "/logout",
    element: <Logout />,
  },
  {
    path: "/",
    element: <Home />,
  },
  {
    path: "/dashboard",
    element: <Dashboard />,
  },
  {
    path: "*",
    element: <PageNotFound />,
  }
]);

function App() {
  return (
    <div id="App">
      <main>
        <RouterProvider router={router} />
      </main>
    </div>
  );
}

export default App;
