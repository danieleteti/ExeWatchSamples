namespace ExeWatch.Models;

public sealed class UserIdentity
{
    public string Id { get; set; } = "";
    public string Email { get; set; } = "";
    public string Name { get; set; } = "";

    public bool IsEmpty => string.IsNullOrEmpty(Id) && string.IsNullOrEmpty(Email) && string.IsNullOrEmpty(Name);
}
