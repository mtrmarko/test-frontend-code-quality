import React from "react";
import { render } from 'react-dom';
import { ThemeProvider } from "@chakra-ui/core";

import Header from "./components/Header.jsx";
import Todos from "./components/Todos.jsx";

function App() {
  return (
    <ThemeProvider>
      <Header />
      <Todos />
    </ThemeProvider>
  )
}

const rootElement = document.getElementById("root")
render(<App />, rootElement)
