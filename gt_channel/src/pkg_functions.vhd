-- Package Declaration Section
package pkg_functions is
    
   function log2ceil(m : integer) return integer;
   
end package pkg_functions;
 
-- Package Body Section
package body pkg_functions is
 
   function log2ceil(m : integer) return integer is
   begin
      for i in 0 to integer'high loop
         if 2 ** i >= m then
            return i;
         end if;
      end loop;
   end function log2ceil;
   
end package body pkg_functions;