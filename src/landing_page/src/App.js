import React from "react";
import { BrowserRouter, Routes, Route } from "react-router-dom";

import Landing from "./pages/landing/landing";
import PageNotFound from "./pages/not_found/not_found";

function App() {
  return (
    <div id="App">
      <BrowserRouter>
        <Routes>
          <Route path="/dmps/*" element={<Landing />}/>
          <Route path="*" element={<PageNotFound/>} />
        </Routes>
      </BrowserRouter>
    </div>
  );
}

export default App;
