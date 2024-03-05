import React from "react";
import { BrowserRouter, Routes, Route } from "react-router-dom";

import Home from "./pages/home/home";
import Landing from "./pages/landing/landing";
import Dashboard from "./pages/dashboard/dashboard";
import { Authenticate, Logout, Unauthorized } from "./Auth";

import PageNotFound from "./pages/not_found/not_found";

function App() {
  return (
    <div id="App">
      <main>
      <BrowserRouter>
        <Routes>
          <Route path="/dmps/*" element={<Landing />}/>
          <Route path="/unauthorized" element={<Unauthorized/>} />
          <Route path="/authenticate" element={<Authenticate/>} />
          <Route path="/logout" element={<Logout/>} />
          <Route path="/" element={<Home/>} />
          <Route path="/dashboard" element={<Dashboard/>} />
          <Route path="*" element={<PageNotFound/>} />
        </Routes>
      </BrowserRouter>
      </main>
    </div>
  );
}

export default App;
