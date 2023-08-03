import React from "react";
import { createBrowserRouter, RouterProvider } from "react-router-dom";

import Landing from "./pages/landing/landing";
import PageNotFound from "./pages/not_found/not_found";

const router = createBrowserRouter([
  {
    path: "/dmps/*",
    element: <Landing />,
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
