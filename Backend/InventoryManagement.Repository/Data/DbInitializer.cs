using Microsoft.EntityFrameworkCore;
using InventoryManagement.Repository.Data;

namespace InventoryManagement.Repository.Data
{
    public static class DbInitializer
    {
        public static void Seed(ApplicationDbContext context)
        {
            context.Database.Migrate();
            // Database is created empty. Users can register their own tenant workspaces from the register page.
        }
    }
}
