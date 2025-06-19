package com.anmolsekhon.merchant_service;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import lombok.extern.slf4j.Slf4j;

import java.util.*;

@RestController
@RequestMapping("/api/v1/merchants")
@Slf4j
public class MerchantController {

    // In-memory storage for demo purposes
    private final Map<String, Merchant> merchants = new HashMap<>();
    private int nextId = 1;

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "healthy");
        response.put("service", "merchant-service");
        response.put("timestamp", new Date().toString());
        log.info("Health check requested");
        return ResponseEntity.ok(response);
    }

    @GetMapping
    public ResponseEntity<Map<String, Object>> getAllMerchants() {
        log.info("Getting all merchants, count: {}", merchants.size());
        Map<String, Object> response = new HashMap<>();
        response.put("merchants", new ArrayList<>(merchants.values()));
        response.put("count", merchants.size());
        return ResponseEntity.ok(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Map<String, Object>> getMerchant(@PathVariable String id) {
        log.info("Getting merchant with id: {}", id);
        Merchant merchant = merchants.get(id);
        if (merchant == null) {
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Merchant not found");
            error.put("id", id);
            return ResponseEntity.notFound().build();
        }
        
        Map<String, Object> response = new HashMap<>();
        response.put("merchant", merchant);
        return ResponseEntity.ok(response);
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> createMerchant(@RequestBody Map<String, Object> merchantData) {
        log.info("Creating new merchant: {}", merchantData);
        
        String id = String.valueOf(nextId++);
        String name = (String) merchantData.get("name");
        String email = (String) merchantData.get("email");
        String category = (String) merchantData.get("category");
        
        if (name == null || name.trim().isEmpty()) {
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Merchant name is required");
            return ResponseEntity.badRequest().body(error);
        }
        
        Merchant merchant = new Merchant(id, name, email, category);
        merchants.put(id, merchant);
        
        Map<String, Object> response = new HashMap<>();
        response.put("merchant", merchant);
        response.put("message", "Merchant created successfully");
        
        log.info("Created merchant: {}", merchant);
        return ResponseEntity.status(201).body(response);
    }

    @PutMapping("/{id}")
    public ResponseEntity<Map<String, Object>> updateMerchant(@PathVariable String id, @RequestBody Map<String, Object> merchantData) {
        log.info("Updating merchant with id: {}, data: {}", id, merchantData);
        
        Merchant existingMerchant = merchants.get(id);
        if (existingMerchant == null) {
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Merchant not found");
            error.put("id", id);
            return ResponseEntity.notFound().build();
        }
        
        String name = (String) merchantData.get("name");
        String email = (String) merchantData.get("email");
        String category = (String) merchantData.get("category");
        
        if (name != null) existingMerchant.setName(name);
        if (email != null) existingMerchant.setEmail(email);
        if (category != null) existingMerchant.setCategory(category);
        
        merchants.put(id, existingMerchant);
        
        Map<String, Object> response = new HashMap<>();
        response.put("merchant", existingMerchant);
        response.put("message", "Merchant updated successfully");
        
        log.info("Updated merchant: {}", existingMerchant);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Map<String, Object>> deleteMerchant(@PathVariable String id) {
        log.info("Deleting merchant with id: {}", id);
        
        Merchant merchant = merchants.remove(id);
        if (merchant == null) {
            Map<String, Object> error = new HashMap<>();
            error.put("error", "Merchant not found");
            error.put("id", id);
            return ResponseEntity.notFound().build();
        }
        
        Map<String, Object> response = new HashMap<>();
        response.put("message", "Merchant deleted successfully");
        response.put("deletedMerchant", merchant);
        
        log.info("Deleted merchant: {}", merchant);
        return ResponseEntity.ok(response);
    }
} 