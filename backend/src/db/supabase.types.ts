export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      audit_activity: {
        Row: {
          action: string
          actor: string
          category: string
          created_at: string
          details_json: Json
          id: string
        }
        Insert: {
          action: string
          actor: string
          category: string
          created_at?: string
          details_json: Json
          id: string
        }
        Update: {
          action?: string
          actor?: string
          category?: string
          created_at?: string
          details_json?: Json
          id?: string
        }
        Relationships: []
      }
      card_transactions: {
        Row: {
          amount_major: number
          card_id: string
          category: string
          created_at: string
          currency: string
          id: string
          merchant_name: string
          status: string
          timestamp: string
          user_id: string
        }
        Insert: {
          amount_major: number
          card_id: string
          category: string
          created_at?: string
          currency?: string
          id: string
          merchant_name: string
          status?: string
          timestamp?: string
          user_id: string
        }
        Update: {
          amount_major?: number
          card_id?: string
          category?: string
          created_at?: string
          currency?: string
          id?: string
          merchant_name?: string
          status?: string
          timestamp?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "card_transactions_card_id_fkey"
            columns: ["card_id"]
            isOneToOne: false
            referencedRelation: "virtual_cards"
            referencedColumns: ["id"]
          },
        ]
      }
      employees: {
        Row: {
          bmoni_user_id: string | null
          card_id: string | null
          country: string
          created_at: string
          email: string
          failed_stage: string | null
          first_name: string
          id: string
          last_name: string
          partner_id: string
          payroll_amount_minor: number
          payroll_currency: string | null
          phone_number: string | null
          status: string
          target_currency: string
          updated_at: string
          wallet_address: string | null
          wallet_id: string | null
        }
        Insert: {
          bmoni_user_id?: string | null
          card_id?: string | null
          country: string
          created_at?: string
          email: string
          failed_stage?: string | null
          first_name: string
          id: string
          last_name: string
          partner_id: string
          payroll_amount_minor?: number
          payroll_currency?: string | null
          phone_number?: string | null
          status?: string
          target_currency: string
          updated_at?: string
          wallet_address?: string | null
          wallet_id?: string | null
        }
        Update: {
          bmoni_user_id?: string | null
          card_id?: string | null
          country?: string
          created_at?: string
          email?: string
          failed_stage?: string | null
          first_name?: string
          id?: string
          last_name?: string
          partner_id?: string
          payroll_amount_minor?: number
          payroll_currency?: string | null
          phone_number?: string | null
          status?: string
          target_currency?: string
          updated_at?: string
          wallet_address?: string | null
          wallet_id?: string | null
        }
        Relationships: []
      }
      invoices: {
        Row: {
          amount_minor: number
          client_email: string | null
          client_name: string
          created_at: string
          currency: string
          description: string | null
          due_date: string | null
          id: string
          invoice_number: string
          payment_link: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_minor: number
          client_email?: string | null
          client_name: string
          created_at?: string
          currency?: string
          description?: string | null
          due_date?: string | null
          id: string
          invoice_number: string
          payment_link?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_minor?: number
          client_email?: string | null
          client_name?: string
          created_at?: string
          currency?: string
          description?: string | null
          due_date?: string | null
          id?: string
          invoice_number?: string
          payment_link?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      money_missions: {
        Row: {
          action_json: Json
          condition_json: Json
          created_at: string
          description: string
          id: string
          is_active: boolean
          rule_type: string
          title: string
          updated_at: string
        }
        Insert: {
          action_json: Json
          condition_json: Json
          created_at?: string
          description: string
          id: string
          is_active?: boolean
          rule_type: string
          title: string
          updated_at?: string
        }
        Update: {
          action_json?: Json
          condition_json?: Json
          created_at?: string
          description?: string
          id?: string
          is_active?: boolean
          rule_type?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      payroll_items: {
        Row: {
          country: string
          created_at: string
          employee_id: string
          employee_name: string
          exchange_rate: number
          id: string
          payroll_run_id: string
          proposal_id: string | null
          status: string
          target_amount_minor: number
          target_currency: string
          usd_amount_minor: number
        }
        Insert: {
          country: string
          created_at?: string
          employee_id: string
          employee_name: string
          exchange_rate: number
          id: string
          payroll_run_id: string
          proposal_id?: string | null
          status?: string
          target_amount_minor: number
          target_currency: string
          usd_amount_minor: number
        }
        Update: {
          country?: string
          created_at?: string
          employee_id?: string
          employee_name?: string
          exchange_rate?: number
          id?: string
          payroll_run_id?: string
          proposal_id?: string | null
          status?: string
          target_amount_minor?: number
          target_currency?: string
          usd_amount_minor?: number
        }
        Relationships: [
          {
            foreignKeyName: "payroll_items_payroll_run_id_fkey"
            columns: ["payroll_run_id"]
            isOneToOne: false
            referencedRelation: "payroll_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      payroll_runs: {
        Row: {
          created_at: string
          employee_count: number
          executed_at: string
          fee_usd_minor: number
          id: string
          reference: string | null
          status: string
          title: string
          total_usd_minor: number
        }
        Insert: {
          created_at?: string
          employee_count: number
          executed_at?: string
          fee_usd_minor?: number
          id: string
          reference?: string | null
          status?: string
          title: string
          total_usd_minor: number
        }
        Update: {
          created_at?: string
          employee_count?: number
          executed_at?: string
          fee_usd_minor?: number
          id?: string
          reference?: string | null
          status?: string
          title?: string
          total_usd_minor?: number
        }
        Relationships: []
      }
      pending_approvals: {
        Row: {
          amount_minor: number
          approval_type: string
          created_at: string
          currency: string
          description: string
          exchange_rate: number | null
          expires_at: string | null
          id: string
          metadata_json: Json
          recipient: string | null
          rule_id: string | null
          status: string
          target_amount_minor: number | null
          target_currency: string | null
          title: string
          user_id: string
        }
        Insert: {
          amount_minor: number
          approval_type: string
          created_at?: string
          currency: string
          description: string
          exchange_rate?: number | null
          expires_at?: string | null
          id: string
          metadata_json?: Json
          recipient?: string | null
          rule_id?: string | null
          status?: string
          target_amount_minor?: number | null
          target_currency?: string | null
          title: string
          user_id: string
        }
        Update: {
          amount_minor?: number
          approval_type?: string
          created_at?: string
          currency?: string
          description?: string
          exchange_rate?: number | null
          expires_at?: string | null
          id?: string
          metadata_json?: Json
          recipient?: string | null
          rule_id?: string | null
          status?: string
          target_amount_minor?: number | null
          target_currency?: string | null
          title?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pending_approvals_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "money_missions"
            referencedColumns: ["id"]
          },
        ]
      }
      smart_wallets: {
        Row: {
          address: string
          bmoni_wallet_id: string | null
          chain: string
          created_at: string
          currency: string
          id: string
          status: string
          updated_at: string
          user_id: string
          user_owner_address: string
        }
        Insert: {
          address: string
          bmoni_wallet_id?: string | null
          chain?: string
          created_at?: string
          currency: string
          id: string
          status?: string
          updated_at?: string
          user_id: string
          user_owner_address: string
        }
        Update: {
          address?: string
          bmoni_wallet_id?: string | null
          chain?: string
          created_at?: string
          currency?: string
          id?: string
          status?: string
          updated_at?: string
          user_id?: string
          user_owner_address?: string
        }
        Relationships: []
      }
      transfers: {
        Row: {
          amount_minor: number
          created_at: string
          currency: string
          exchange_rate: number | null
          executed_at: string | null
          fee_minor: number | null
          funding_currency: string
          funding_wallet_id: string
          id: string
          proposal_id: string | null
          purpose: string | null
          recipient: string
          recipient_address: string | null
          status: string
          total_debit_minor: number
          transaction_hash: string | null
          user_id: string
        }
        Insert: {
          amount_minor: number
          created_at?: string
          currency: string
          exchange_rate?: number | null
          executed_at?: string | null
          fee_minor?: number | null
          funding_currency: string
          funding_wallet_id: string
          id: string
          proposal_id?: string | null
          purpose?: string | null
          recipient: string
          recipient_address?: string | null
          status?: string
          total_debit_minor: number
          transaction_hash?: string | null
          user_id: string
        }
        Update: {
          amount_minor?: number
          created_at?: string
          currency?: string
          exchange_rate?: number | null
          executed_at?: string | null
          fee_minor?: number | null
          funding_currency?: string
          funding_wallet_id?: string
          id?: string
          proposal_id?: string | null
          purpose?: string | null
          recipient?: string
          recipient_address?: string | null
          status?: string
          total_debit_minor?: number
          transaction_hash?: string | null
          user_id?: string
        }
        Relationships: []
      }
      users: {
        Row: {
          account_type: string
          bmoni_user_id: string | null
          company_name: string | null
          company_role: string | null
          country: string
          created_at: string
          email: string
          full_name: string
          id: string
          kyc_status: string
          national_id: string | null
          phone_number: string | null
          updated_at: string
        }
        Insert: {
          account_type?: string
          bmoni_user_id?: string | null
          company_name?: string | null
          company_role?: string | null
          country?: string
          created_at?: string
          email: string
          full_name: string
          id: string
          kyc_status?: string
          national_id?: string | null
          phone_number?: string | null
          updated_at?: string
        }
        Update: {
          account_type?: string
          bmoni_user_id?: string | null
          company_name?: string | null
          company_role?: string | null
          country?: string
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          kyc_status?: string
          national_id?: string | null
          phone_number?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      virtual_cards: {
        Row: {
          bmoni_card_id: string | null
          card_color: string
          card_name: string
          card_type: string
          created_at: string
          currency: string
          employee_id: string | null
          expiration_date: string
          id: string
          is_reserved: boolean
          last4: string
          masked_pan: string
          monthly_spend_limit_minor: number | null
          proposal_id: string | null
          smart_wallet_id: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          bmoni_card_id?: string | null
          card_color?: string
          card_name: string
          card_type?: string
          created_at?: string
          currency?: string
          employee_id?: string | null
          expiration_date: string
          id: string
          is_reserved?: boolean
          last4: string
          masked_pan: string
          monthly_spend_limit_minor?: number | null
          proposal_id?: string | null
          smart_wallet_id: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          bmoni_card_id?: string | null
          card_color?: string
          card_name?: string
          card_type?: string
          created_at?: string
          currency?: string
          employee_id?: string | null
          expiration_date?: string
          id?: string
          is_reserved?: boolean
          last4?: string
          masked_pan?: string
          monthly_spend_limit_minor?: number | null
          proposal_id?: string | null
          smart_wallet_id?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "virtual_cards_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_events: {
        Row: {
          bmoni_event_id: string | null
          event_type: string
          id: string
          payload_json: Json
          processed_at: string
        }
        Insert: {
          bmoni_event_id?: string | null
          event_type: string
          id: string
          payload_json: Json
          processed_at?: string
        }
        Update: {
          bmoni_event_id?: string | null
          event_type?: string
          id?: string
          payload_json?: Json
          processed_at?: string
        }
        Relationships: []
      }
      webhook_subscriptions: {
        Row: {
          active: boolean
          callback_url: string
          created_at: string
          events: Json
          id: string
          partner_id: string
          secret_key: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          callback_url: string
          created_at?: string
          events?: Json
          id: string
          partner_id: string
          secret_key?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          callback_url?: string
          created_at?: string
          events?: Json
          id?: string
          partner_id?: string
          secret_key?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
