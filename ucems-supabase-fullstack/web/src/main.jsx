import React, {Component, useEffect, useState} from 'react';
import {createRoot} from 'react-dom/client';
import App from './App.jsx';
import './style.css';
import './club-cards.css';

class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = {error: null};
  }

  static getDerivedStateFromError(error) {
    return {error};
  }

  render() {
    if (this.state.error) {
      return (
        <main className="auth-wrap" role="alert">
          <section className="auth-card">
            <span className="eyebrow danger">APPLICATION ERROR</span>
            <h1>We could not load UniEvents</h1>
            <p>{this.state.error.message || 'An unexpected error occurred.'}</p>
            <button className="btn btn-primary" onClick={() => window.location.reload()}>
              Reload
            </button>
          </section>
        </main>
      );
    }
    return this.props.children;
  }
}

createRoot(document.getElementById('app')).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>,
);
