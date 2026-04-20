import { useQuery } from "@tanstack/react-query";
import { fetchCurrentUser } from "../api/auth";

export function useAuth() {
  return useQuery({
    queryKey: ["auth"],
    queryFn: fetchCurrentUser,
    retry: false,
    staleTime: 5 * 60 * 1000,
  });
}
