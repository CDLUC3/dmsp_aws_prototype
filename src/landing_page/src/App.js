import React from "react";
import { BrowserRouter, Routes, Route } from "react-router-dom";

import Landing from "./pages/landing/landing";
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
