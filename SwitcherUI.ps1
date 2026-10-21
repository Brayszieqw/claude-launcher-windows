param([string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'ClaudeSwitcherWindows'),[switch]$StartHidden)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'diagnostic-reports.ps1')
. (Join-Path $PSScriptRoot 'flclash-checks.ps1')
. (Join-Path $PSScriptRoot 'guard-runtime.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
[void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'ClaudeLauncher.exe'))
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Claude 启动助手 · 夕照拥抱" Width="1180" Height="820" MinWidth="760" MinHeight="660" WindowStartupLocation="CenterScreen" WindowStyle="SingleBorderWindow" ResizeMode="CanResize" Background="#2B1F1A" Foreground="#FFF1DB" FontFamily="Microsoft YaHei UI, Microsoft YaHei, Segoe UI" FontSize="14" UseLayoutRounding="True" SnapsToDevicePixels="True" TextOptions.TextFormattingMode="Display" xml:lang="zh-CN">
  <Window.Resources>
    <FontFamily x:Key="IconFont">Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol</FontFamily>
    <FontFamily x:Key="SerifFont">SimSun, Microsoft YaHei UI</FontFamily>
    <Thickness x:Key="PanelMargin">22,80,22,22</Thickness>

    <Style x:Key="FocusRing">
      <Setter Property="Control.Template">
        <Setter.Value>
          <ControlTemplate>
            <Rectangle Margin="-3" RadiusX="10" RadiusY="10" Stroke="#F1C296" StrokeThickness="2" SnapsToDevicePixels="True" />
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="FocusRingLight">
      <Setter Property="Control.Template">
        <Setter.Value>
          <ControlTemplate>
            <Rectangle Margin="-3" RadiusX="10" RadiusY="10" Stroke="#FFF1DB" StrokeThickness="2" SnapsToDevicePixels="True" />
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="FocusRingInset">
      <Setter Property="Control.Template">
        <Setter.Value>
          <ControlTemplate>
            <Rectangle Margin="2" RadiusX="6" RadiusY="6" Stroke="#F1C296" StrokeThickness="2" SnapsToDevicePixels="True" />
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Icon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="{StaticResource IconFont}" />
      <Setter Property="FontSize" Value="14" />
      <Setter Property="FontWeight" Value="Normal" />
      <Setter Property="VerticalAlignment" Value="Center" />
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#14FFE9CC" />
      <Setter Property="BorderBrush" Value="#33F1D5B4" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="CornerRadius" Value="12" />
    </Style>
    <Style x:Key="GlassPanel" TargetType="Border">
      <Setter Property="Margin" Value="{DynamicResource PanelMargin}" />
      <Setter Property="Padding" Value="2,4" />
      <Setter Property="CornerRadius" Value="14" />
      <Setter Property="BorderBrush" Value="#4DFFE1B5" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="Tag" Value="Glass" />
      <Setter Property="TextElement.Foreground" Value="#FFF1DB" />
      <Setter Property="Background">
        <Setter.Value>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#EA281C16" Offset="0" /><GradientStop Color="#DE372820" Offset="1" /></LinearGradientBrush>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PageTitle" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="{StaticResource SerifFont}" />
      <Setter Property="FontSize" Value="25" />
      <Setter Property="Foreground" Value="#FFF1DB" />
      <Setter Property="Margin" Value="0,0,14,0" />
    </Style>
    <Style x:Key="PageSub" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#DEC5AD" />
      <Setter Property="FontSize" Value="13" />
      <Setter Property="VerticalAlignment" Value="Bottom" />
      <Setter Property="Margin" Value="0,0,0,4" />
      <Setter Property="TextWrapping" Value="Wrap" />
    </Style>
    <Style x:Key="H2" TargetType="TextBlock">
      <Setter Property="FontSize" Value="16" />
      <Setter Property="FontWeight" Value="Bold" />
      <Setter Property="Foreground" Value="#FFF1DB" />
    </Style>

    <ControlTemplate x:Key="BtnTpl" TargetType="Button">
      <Border x:Name="Bd" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" SnapsToDevicePixels="True">
        <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="False" />
      </Border>
    </ControlTemplate>
    <Style x:Key="BtnBase" TargetType="Button">
      <Setter Property="Template" Value="{StaticResource BtnTpl}" />
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}" />
      <Setter Property="Cursor" Value="Hand" />
      <Setter Property="Height" Value="40" />
      <Setter Property="Padding" Value="16,0" />
      <Setter Property="FontSize" Value="14" />
      <Setter Property="BorderThickness" Value="0" />
      <Setter Property="BorderBrush" Value="Transparent" />
      <Setter Property="Background" Value="Transparent" />
      <Style.Triggers>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Cursor" Value="Arrow" />
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Background" Value="#E1B383" />
      <Setter Property="Foreground" Value="#493122" />
      <Setter Property="BorderBrush" Value="#F6CFA0" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="FontWeight" Value="Bold" />
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#F2C896" />
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="#26E1B383" />
          <Setter Property="Foreground" Value="#B59C86" />
          <Setter Property="BorderBrush" Value="#33F1D5B4" />
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Background" Value="#2BE1B383" />
      <Setter Property="Foreground" Value="#F8DCC0" />
      <Setter Property="BorderBrush" Value="#4DE9C6A0" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="FontWeight" Value="Bold" />
      <Setter Property="Padding" Value="14,0" />
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#45E1B383" />
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
          <Setter Property="Background" Value="#60E1B383" />
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Background" Value="#14FFE9CC" />
          <Setter Property="Foreground" Value="#A88E78" />
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="GhostButton" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Foreground" Value="#F1C296" />
      <Setter Property="FontWeight" Value="Bold" />
      <Setter Property="FontSize" Value="13" />
      <Setter Property="Height" Value="32" />
      <Setter Property="Padding" Value="10,0" />
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#1FFFE9CC" />
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
          <Setter Property="Background" Value="#38FFE9CC" />
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Foreground" Value="#A88E78" />
          <Setter Property="Opacity" Value="0.6" />
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="OutlineButton" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Background" Value="#0FFFE9CC" />
      <Setter Property="Foreground" Value="#F8DCC0" />
      <Setter Property="BorderBrush" Value="#66E9C6A0" />
      <Setter Property="BorderThickness" Value="1" />
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#1FFFE9CC" />
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Opacity" Value="0.6" />
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="OutlineDangerButton" TargetType="Button" BasedOn="{StaticResource OutlineButton}">
      <Setter Property="Foreground" Value="#FFB4A6" />
      <Setter Property="BorderBrush" Value="#66FF9C8C" />
      <Setter Property="FontWeight" Value="Bold" />
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#26FF8A73" />
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="HugPrimary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRingLight}" />
      <Setter Property="Background" Value="#E1B383" />
      <Setter Property="Foreground" Value="#493122" />
      <Setter Property="BorderBrush" Value="#F6CFA0" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="FontWeight" Value="Bold" />
      <Setter Property="Height" Value="40" />
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#F2C896" />
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Opacity" Value="0.55" />
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="HugSecondary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRingLight}" />
      <Setter Property="Background" Value="#2B6F4A30" />
      <Setter Property="Foreground" Value="#F8DCC0" />
      <Setter Property="BorderBrush" Value="#66E9C6A0" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="FontWeight" Value="Bold" />
      <Setter Property="Height" Value="40" />
      <Setter Property="Padding" Value="14,0" />
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#4D6F4A30" />
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Opacity" Value="0.5" />
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="CardLink" TargetType="Button">
      <Setter Property="Foreground" Value="#F1C296" />
      <Setter Property="FontSize" Value="12" />
      <Setter Property="Cursor" Value="Hand" />
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRingLight}" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="5" Padding="6,3">
              <ContentPresenter VerticalAlignment="Center" RecognizesAccessKey="False" />
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1FEFD0A8" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="NavPill" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#F3DDC8" />
      <Setter Property="FontSize" Value="12" />
      <Setter Property="Cursor" Value="Hand" />
      <Setter Property="Margin" Value="1,0" />
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRingLight}" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bd" CornerRadius="6" Background="Transparent" Padding="11,8">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" FontFamily="Segoe UI Symbol" FontSize="14" Foreground="{TemplateBinding Foreground}" VerticalAlignment="Center" />
                <ContentPresenter Margin="7,0,0,0" VerticalAlignment="Center" />
              </StackPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1FEFD0A8" />
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#33EFD0A8" />
                <Setter Property="Foreground" Value="#FFF3E1" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="RowToggle" TargetType="ToggleButton">
      <Setter Property="Background" Value="Transparent" />
      <Setter Property="Foreground" Value="#FFF1DB" />
      <Setter Property="HorizontalContentAlignment" Value="Stretch" />
      <Setter Property="Padding" Value="16,11,16,11" />
      <Setter Property="Cursor" Value="Hand" />
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRingInset}" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*" />
                  <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Top" />
                <TextBlock x:Name="Chev" Grid.Column="1" Text="&#xE76C;" FontFamily="{StaticResource IconFont}" FontSize="12" Foreground="#CDB39B" Margin="12,6,0,0" VerticalAlignment="Top" RenderTransformOrigin="0.5,0.5">
                  <TextBlock.RenderTransform>
                    <RotateTransform Angle="0" />
                  </TextBlock.RenderTransform>
                </TextBlock>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#14FFE9CC" />
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Chev" Property="RenderTransform">
                  <Setter.Value>
                    <RotateTransform Angle="90" />
                  </Setter.Value>
                </Setter>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="AcctItem" TargetType="ListBoxItem">
      <Setter Property="Margin" Value="0,0,0,10" />
      <Setter Property="Padding" Value="0" />
      <Setter Property="Foreground" Value="#FFF1DB" />
      <Setter Property="HorizontalContentAlignment" Value="Stretch" />
      <Setter Property="Cursor" Value="Hand" />
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Grid>
              <Border x:Name="Bd" CornerRadius="10" Background="#14FFE9CC" BorderBrush="#33F1D5B4" BorderThickness="1">
                <ContentPresenter HorizontalAlignment="Stretch" />
              </Border>
              <Border x:Name="Sel" CornerRadius="10" BorderBrush="#E1B383" BorderThickness="2" Visibility="Collapsed" IsHitTestVisible="False" />
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1FFFE9CC" />
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#26FFE9CC" />
                <Setter TargetName="Sel" Property="Visibility" Value="Visible" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Field" TargetType="TextBox">
      <Setter Property="Height" Value="40" />
      <Setter Property="Padding" Value="10,0" />
      <Setter Property="FontSize" Value="14" />
      <Setter Property="VerticalContentAlignment" Value="Center" />
      <Setter Property="Foreground" Value="#FFF1DB" />
      <Setter Property="CaretBrush" Value="#FFF1DB" />
      <Setter Property="SelectionBrush" Value="#E1B383" />
      <Setter Property="Background" Value="#1FFFE9CC" />
      <Setter Property="BorderBrush" Value="#66E9C6A0" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden" />
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#E1B383" />
                <Setter TargetName="Bd" Property="BorderThickness" Value="2" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button" BasedOn="{StaticResource SecondaryButton}" />
    <Style TargetType="TextBox" BasedOn="{StaticResource Field}" />

    <Style TargetType="TabItem">
      <!-- Page content inherits its text colour from the TabItem, whose system default is black. -->
      <Setter Property="Foreground" Value="#FFF1DB" />
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="#F22E211A" />
      <Setter Property="Foreground" Value="#FFF1DB" />
      <Setter Property="BorderBrush" Value="#66E9C6A0" />
      <Setter Property="FontSize" Value="12" />
      <Setter Property="Padding" Value="9,6" />
    </Style>

    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10" />
      <Setter Property="MinWidth" Value="10" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border CornerRadius="4" Background="#59F1D5B4" Margin="2" />
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto" />
          <Setter Property="MinWidth" Value="0" />
          <Setter Property="Height" Value="10" />
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Grid Background="Transparent">
                  <Track x:Name="PART_Track">
                    <Track.Thumb>
                      <Thumb>
                        <Thumb.Template>
                          <ControlTemplate TargetType="Thumb">
                            <Border CornerRadius="4" Background="#59F1D5B4" Margin="2" />
                          </ControlTemplate>
                        </Thumb.Template>
                      </Thumb>
                    </Track.Thumb>
                  </Track>
                </Grid>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#FFF1DB" />
      <Setter Property="Background" Value="#1FFFE9CC" />
      <Setter Property="BorderBrush" Value="#66E9C6A0" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="MinHeight" Value="38" />
      <Setter Property="Padding" Value="10,6" />
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}" />
      <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled" />
      <Setter Property="ScrollViewer.VerticalScrollBarVisibility" Value="Auto" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Focusable="False" ClickMode="Press" Cursor="Hand" IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Box" CornerRadius="8" Background="{Binding Background, RelativeSource={RelativeSource AncestorType=ComboBox}}" BorderBrush="{Binding BorderBrush, RelativeSource={RelativeSource AncestorType=ComboBox}}" BorderThickness="1">
                      <TextBlock Text="&#xE70D;" FontFamily="{StaticResource IconFont}" FontSize="11" Foreground="#F1C296" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0" />
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Box" Property="BorderBrush" Value="#E1B383" />
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter IsHitTestVisible="False" Margin="{TemplateBinding Padding}" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}" VerticalAlignment="Center" HorizontalAlignment="Left" />
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                <Border Background="#F22E211A" BorderBrush="#66E9C6A0" BorderThickness="1" CornerRadius="8" Margin="0,4,0,0" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                  <ScrollViewer Margin="4" SnapsToDevicePixels="True">
                    <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained" />
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.55" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#FFF1DB" />
      <Setter Property="Padding" Value="10,7" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter />
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#33E1B383" />
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#4DE1B383" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E5CDB4" />
      <Setter Property="Cursor" Value="Hand" />
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Box" Width="16" Height="16" CornerRadius="4" BorderBrush="#99E9C6A0" BorderThickness="1" Background="#1FFFE9CC" VerticalAlignment="Center">
                <TextBlock x:Name="Mark" Text="&#xE73E;" FontFamily="{StaticResource IconFont}" FontSize="11" Foreground="#2E211A" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed" />
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center" />
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="#E1B383" />
                <Setter TargetName="Mark" Property="Visibility" Value="Visible" />
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Box" Property="BorderBrush" Value="#F6CFA0" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="Expander">
      <Setter Property="Foreground" Value="#F1C296" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Expander">
            <StackPanel>
              <ToggleButton Cursor="Hand" FocusVisualStyle="{StaticResource FocusRing}" IsChecked="{Binding IsExpanded, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <StackPanel Orientation="Horizontal" Background="Transparent">
                      <TextBlock x:Name="Chev" Text="&#xE76C;" FontFamily="{StaticResource IconFont}" FontSize="10" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Expander}}" VerticalAlignment="Center" Margin="0,0,7,0" RenderTransformOrigin="0.5,0.5">
                        <TextBlock.RenderTransform>
                          <RotateTransform Angle="0" />
                        </TextBlock.RenderTransform>
                      </TextBlock>
                      <ContentPresenter Content="{Binding Header, RelativeSource={RelativeSource AncestorType=Expander}}" TextElement.Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Expander}}" VerticalAlignment="Center" />
                    </StackPanel>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsChecked" Value="True">
                        <Setter TargetName="Chev" Property="RenderTransform">
                          <Setter.Value>
                            <RotateTransform Angle="90" />
                          </Setter.Value>
                        </Setter>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter x:Name="Body" Visibility="Collapsed" />
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsExpanded" Value="True">
                <Setter TargetName="Body" Property="Visibility" Value="Visible" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

<DataTemplate x:Key="CheckRow">
 <Border BorderBrush="#26F1D5B4" BorderThickness="0,1,0,0" Padding="16,14">
  <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="76" /><ColumnDefinition Width="140" /><ColumnDefinition Width="*" /></Grid.ColumnDefinitions>
   <Border Background="{Binding Badge}" CornerRadius="10" Padding="6,3" VerticalAlignment="Top" Margin="0,0,12,0"><TextBlock Text="{Binding Label}" Foreground="{Binding Color}" FontSize="12" TextAlignment="Center" /></Border>
   <TextBlock Grid.Column="1" Text="{Binding Name}" FontWeight="SemiBold" FontSize="13" TextWrapping="Wrap" Margin="0,1,12,0" />
   <StackPanel Grid.Column="2"><TextBlock Text="{Binding Detail}" TextWrapping="Wrap" FontSize="13" Foreground="#E2C8AF" LineHeight="22" />
    <Expander Header="来源与测量细节" Visibility="{Binding EvidenceVisibility}" FontSize="12" Foreground="#F1C296" Margin="0,8,0,0">
     <StackPanel Margin="0,8,0,0"><TextBlock Text="{Binding Source}" TextWrapping="Wrap" Foreground="#CDB39B" Margin="0,0,0,6" />
      <TextBox Text="{Binding Evidence, Mode=OneWay}" IsReadOnly="True" TextWrapping="Wrap" Height="Auto" MinHeight="0" BorderThickness="0" Padding="0" Background="Transparent" FontFamily="Consolas, Microsoft YaHei UI" FontSize="12" />
      <TextBlock Text="{Binding Advice}" TextWrapping="Wrap" Foreground="#CDB39B" Margin="0,6,0,0" />
     </StackPanel>
    </Expander>
   </StackPanel>
  </Grid>
 </Border>
</DataTemplate>
<Style x:Key="GroupExpander" TargetType="Expander">
 <Setter Property="HorizontalContentAlignment" Value="Stretch" />
 <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Expander"><StackPanel>
  <ToggleButton Style="{StaticResource RowToggle}" IsChecked="{Binding IsExpanded, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}" Content="{TemplateBinding Header}" ContentTemplate="{TemplateBinding HeaderTemplate}" />
  <ContentPresenter x:Name="Body" Visibility="Collapsed" />
 </StackPanel><ControlTemplate.Triggers><Trigger Property="IsExpanded" Value="True"><Setter TargetName="Body" Property="Visibility" Value="Visible" /></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
</Style>
<DataTemplate x:Key="CheckGroup">
 <Border BorderBrush="#26F1D5B4" BorderThickness="0,1,0,0"><Expander Style="{StaticResource GroupExpander}">
  <Expander.Header><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="76" /><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
   <Border Background="{Binding Badge}" CornerRadius="10" Padding="6,3" Margin="0,0,12,0" VerticalAlignment="Center"><TextBlock Text="{Binding Label}" Foreground="{Binding Color}" FontSize="12" TextAlignment="Center" /></Border>
   <StackPanel Grid.Column="1"><TextBlock Text="{Binding Name}" FontWeight="SemiBold" /><TextBlock Text="{Binding Summary}" Foreground="#CDB39B" FontSize="12" TextWrapping="Wrap" Margin="0,3,12,0" /></StackPanel>
   <TextBlock Grid.Column="2" Text="{Binding CountLabel}" Foreground="#CDB39B" FontSize="12" VerticalAlignment="Center" />
  </Grid></Expander.Header>
  <ItemsControl ItemsSource="{Binding Items}" ItemTemplate="{StaticResource CheckRow}" />
 </Expander></Border>
</DataTemplate>
<DataTemplate x:Key="MetricCard"><Border Background="#1AFFE9CC" CornerRadius="8" Padding="12,9" Margin="4,0"><StackPanel><TextBlock Text="{Binding Label}" Foreground="#CDB39B" FontSize="12" /><TextBlock Text="{Binding Count}" Foreground="{Binding Color}" FontSize="22" FontWeight="Bold" Margin="0,2,0,0" /></StackPanel></Border></DataTemplate>
<ItemsPanelTemplate x:Key="MetricPanel"><UniformGrid Columns="4" /></ItemsPanelTemplate>
<DataTemplate x:Key="BasicTile"><Border Style="{StaticResource Card}" Padding="10,8" Margin="4,0,4,8"><StackPanel><TextBlock Text="{Binding Name}" Foreground="#CDB39B" FontSize="12" TextTrimming="CharacterEllipsis" /><TextBlock Text="{Binding Label}" Foreground="{Binding Color}" FontWeight="Bold" Margin="0,4,0,0" /></StackPanel></Border></DataTemplate>
<DataTemplate x:Key="AccountCard">
 <Grid Margin="16"><Grid.ColumnDefinitions><ColumnDefinition Width="28" /><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
  <Grid Width="16" Height="16" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="0,5,0,0"><Ellipse Stroke="#A88E78" StrokeThickness="1.5" /><Ellipse Width="8" Height="8" Fill="#F1C296"><Ellipse.Style><Style TargetType="Ellipse"><Setter Property="Visibility" Value="Collapsed" /><Style.Triggers><DataTrigger Binding="{Binding IsSelected, RelativeSource={RelativeSource AncestorType=ListBoxItem}}" Value="True"><Setter Property="Visibility" Value="Visible" /></DataTrigger></Style.Triggers></Style></Ellipse.Style></Ellipse></Grid>
  <StackPanel Grid.Column="1" Margin="0,0,12,0"><WrapPanel><TextBlock Text="{Binding Name}" FontSize="16" FontWeight="Bold" TextWrapping="Wrap" MaxWidth="320" Margin="0,0,10,4" />
   <Border CornerRadius="9" Padding="8,2" Background="#2E7BE0A6" Margin="0,0,6,4"><Border.Style><Style TargetType="Border"><Setter Property="Visibility" Value="Collapsed" /><Style.Triggers><DataTrigger Binding="{Binding IsCurrent}" Value="True"><Setter Property="Visibility" Value="Visible" /></DataTrigger></Style.Triggers></Style></Border.Style><TextBlock Text="正在使用" Foreground="#9BE0B4" FontSize="12" /></Border>
   <Border CornerRadius="9" Padding="8,2" Background="#26E1B383" Margin="0,0,0,4"><Border.Style><Style TargetType="Border"><Setter Property="Visibility" Value="Collapsed" /><Style.Triggers><DataTrigger Binding="{Binding IsSelected, RelativeSource={RelativeSource AncestorType=ListBoxItem}}" Value="True"><Setter Property="Visibility" Value="Visible" /></DataTrigger></Style.Triggers></Style></Border.Style><TextBlock Text="已选中" Foreground="#F1C296" FontSize="12" /></Border>
  </WrapPanel><TextBlock Text="{Binding Session}" Foreground="#CDB39B" FontSize="13" Margin="0,4,0,0" TextWrapping="Wrap" /><TextBlock Text="{Binding Baseline}" Foreground="#CDB39B" FontSize="13" Margin="0,4,0,0" TextWrapping="Wrap" /></StackPanel>
  <Button Grid.Column="2" Tag="RenameAccount" Content="重命名" Style="{StaticResource GhostButton}" VerticalAlignment="Top" AutomationProperties.Name="重命名账号" />
 </Grid>
</DataTemplate>

<DataTemplate x:Key="AddressCard"><Border Style="{StaticResource Card}" Margin="0,0,8,8" Padding="16,12"><StackPanel>
 <DockPanel><TextBlock DockPanel.Dock="Right" Text="{Binding Label}" Foreground="{Binding Color}" FontSize="12" Margin="8,0,0,0"/><TextBlock Text="{Binding Title}" FontWeight="Bold" FontSize="13" TextWrapping="Wrap"/></DockPanel>
 <TextBox Text="{Binding Address, Mode=OneWay}" IsReadOnly="True" Height="Auto" MinHeight="26" BorderThickness="0" Padding="0" Margin="0,8,0,6" Background="Transparent" FontFamily="Consolas, Microsoft YaHei UI" Foreground="#F1C296" FontSize="17" TextWrapping="Wrap"/>
 <TextBlock Text="{Binding Detail}" Foreground="#CDB39B" FontSize="12" TextWrapping="Wrap" LineHeight="20"/>
</StackPanel></Border></DataTemplate>
    <DataTemplate x:Key="DotTile">
      <Ellipse Width="9" Height="9" Margin="0,0,5,0" Fill="{Binding Color}" VerticalAlignment="Center">
        <Ellipse.ToolTip>
          <TextBlock><Run Text="{Binding Name, Mode=OneWay}" /><Run Text=" · " /><Run Text="{Binding Label, Mode=OneWay}" /></TextBlock>
        </Ellipse.ToolTip>
      </Ellipse>
    </DataTemplate>
  </Window.Resources>

  <Grid x:Name="Root">
    <Grid.RowDefinitions>
      <RowDefinition Height="*" />
      <RowDefinition Height="Auto" />
    </Grid.RowDefinitions>

    <Grid x:Name="MainContent">
      <Grid x:Name="HugStage" ClipToBounds="True" AutomationProperties.Name="夕照拥抱">
        <Border>
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#E9BC8F" Offset="0" /><GradientStop Color="#9C6A55" Offset="1" /></LinearGradientBrush>
          </Border.Background>
        </Border>
        <Canvas x:Name="HugCanvas" IsHitTestVisible="False">
          <MediaElement x:Name="HugMotion" LoadedBehavior="Manual" UnloadedBehavior="Manual" ScrubbingEnabled="True" IsMuted="True" Stretch="Fill" RenderOptions.BitmapScalingMode="HighQuality" />
          <Image x:Name="HugIdle" Stretch="Fill" RenderOptions.BitmapScalingMode="HighQuality" AutomationProperties.Name="Claude 大小姐站在夕阳河畔，抬眼看你" />
          <Image x:Name="HugFinal" Stretch="Fill" RenderOptions.BitmapScalingMode="HighQuality" Opacity="0" AutomationProperties.Name="Claude 大小姐向你张开双臂" />
          <Image x:Name="SceneEmpty" Stretch="Fill" RenderOptions.BitmapScalingMode="HighQuality" Opacity="0" AutomationProperties.Name="夕阳河畔" />
        </Canvas>
        <Canvas x:Name="HugDust" IsHitTestVisible="False" />
        <TextBlock x:Name="HugLine" Text="辛苦啦，抱一下。" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,30" FontFamily="{StaticResource SerifFont}" FontSize="23" Foreground="#FFF8ED" Opacity="0" IsHitTestVisible="False">
          <TextBlock.Effect><DropShadowEffect Color="#5E3929" BlurRadius="10" ShadowDepth="2" Direction="270" Opacity="0.9" /></TextBlock.Effect>
        </TextBlock>
        <StackPanel x:Name="HugCaption" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,28,28" IsHitTestVisible="False">
          <StackPanel.Effect><DropShadowEffect Color="#653E2F" BlurRadius="13" ShadowDepth="2" Direction="270" Opacity="0.85" /></StackPanel.Effect>
          <TextBlock Text="夕照 · 拥抱" FontFamily="{StaticResource SerifFont}" FontSize="20" Foreground="#FFF4DF" HorizontalAlignment="Right" />
          <TextBlock Text="STAY A LITTLE CLOSER" FontSize="9" Foreground="#FFF4DF" HorizontalAlignment="Right" Margin="0,9,0,0" />
        </StackPanel>
      </Grid>

      <Grid x:Name="GlassLayer" IsHitTestVisible="False">
        <Canvas>
          <Image x:Name="GlassImage" Stretch="Fill">
            <Image.Effect><BlurEffect Radius="36" KernelType="Gaussian" RenderingBias="Performance" /></Image.Effect>
          </Image>
        </Canvas>
      </Grid>

      <TabControl x:Name="MainTabs" SelectedIndex="0" BorderThickness="0" Background="Transparent" Padding="0" Focusable="False">
        <TabControl.Template>
          <ControlTemplate TargetType="TabControl"><ContentPresenter ContentSource="SelectedContent" /></ControlTemplate>
        </TabControl.Template>
        <TabItem>
          <Grid x:Name="PageOverview" TextElement.Foreground="#FFF1DB">
            <Border x:Name="HugCard" HorizontalAlignment="Left" VerticalAlignment="Bottom" Width="345" Margin="28,0,0,26" Padding="22,20,22,16" CornerRadius="12" BorderBrush="#4DFFE1B5" BorderThickness="1" Tag="Glass">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#B82E211A" Offset="0" /><GradientStop Color="#8C3E2D21" Offset="1" /></LinearGradientBrush>
              </Border.Background>
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                  <Rectangle Width="21" Height="1" Fill="#DBAE7D" VerticalAlignment="Center" Margin="0,0,10,0" />
                  <TextBlock Text="A LITTLE CLOSER" FontSize="10" Foreground="#F1C296" />
                </StackPanel>
                <TextBlock Text="欢迎回来。" FontFamily="{StaticResource SerifFont}" FontSize="28" Foreground="#FFF1DB" />
                <TextBlock Text="先给你一个拥抱，再开启新的对话。" FontSize="12" Foreground="#EBCCB0" TextWrapping="Wrap" Margin="0,10,0,16" />
                <Border BorderBrush="#33EFD4B6" BorderThickness="0,1,0,0" Padding="0,13,0,0">
                  <StackPanel>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto" /><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
                      <Border Width="31" Height="31" CornerRadius="16" Background="#29E7C297" BorderBrush="#2BF1D5B4" BorderThickness="1" Margin="0,0,10,0" VerticalAlignment="Center">
                        <TextBlock x:Name="HeroAvatarText" Text="C" FontFamily="Georgia, SimSun" FontSize="16" Foreground="#FFE7C9" HorizontalAlignment="Center" VerticalAlignment="Center" />
                      </Border>
                      <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="0,0,8,0">
                        <TextBlock Text="当前账号" FontSize="10" Foreground="#D8B79B" />
                        <TextBlock x:Name="AccountText" FontSize="14" FontWeight="Bold" Foreground="#FFF0DD" TextWrapping="Wrap" Margin="0,2,0,0" Text="正在读取…" />
                      </StackPanel>
                      <Border x:Name="HeroBadge" Grid.Column="2" CornerRadius="9" Background="#24F1D5B4" BorderBrush="#45E6C3A1" BorderThickness="1" Padding="7,2" VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal">
                          <Ellipse Width="6" Height="6" Fill="#7BE0A6" VerticalAlignment="Center" Margin="0,0,5,0" />
                          <TextBlock Text="正在使用" FontSize="11" Foreground="#EDD0B1" />
                        </StackPanel>
                      </Border>
                    </Grid>
                    <Grid Margin="0,13,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto" /><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
                      <ItemsControl x:Name="TileDots" ItemTemplate="{StaticResource DotTile}" VerticalAlignment="Center" Focusable="False">
                        <ItemsControl.ItemsPanel><ItemsPanelTemplate><StackPanel Orientation="Horizontal" /></ItemsPanelTemplate></ItemsControl.ItemsPanel>
                      </ItemsControl>
                      <TextBlock x:Name="CardSummary" Grid.Column="1" Text="5 项尚未检查" FontSize="11" Foreground="#D8B79B" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="3,0,6,0" />
                      <Button x:Name="BtnDetails" Grid.Column="2" Content="查看检查明细 ›" Style="{StaticResource CardLink}" AutomationProperties.Name="查看检查明细" />
                    </Grid>
                    <Grid Margin="0,12,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
                      <Button x:Name="BtnCheck" Content="拥抱一下" Style="{StaticResource HugPrimary}" Margin="0,0,8,0" AutomationProperties.Name="拥抱一下，检查环境" ToolTip="运行基础检查，同时播放拥抱动画；结束后不会自动启动 Claude。" />
                      <Button x:Name="BtnStart" Grid.Column="1" Content="启动 Claude" Style="{StaticResource HugSecondary}" ToolTipService.ShowOnDisabled="True" ToolTip="打开 Claude；网络异常只提醒，不锁定启动。" />
                    </Grid>
                    <TextBlock x:Name="HeroHint" FontSize="11" Foreground="#D8B59A" TextWrapping="Wrap" Margin="0,10,0,0" Text="网络异常只提醒 · 可直接启动 Claude" />
                    <Button x:Name="BtnHomeGuard" Content="守护状态 · 查看实时监测 ›" Style="{StaticResource CardLink}" HorizontalAlignment="Left" Margin="0,6,0,0" AutomationProperties.Name="查看实时监测" />
                  </StackPanel>
                </Border>
              </StackPanel>
            </Border>

            <Border x:Name="DetailsPanel" Style="{StaticResource GlassPanel}" HorizontalAlignment="Right" Width="480" Margin="0,80,22,22" Visibility="Collapsed">
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="*" /></Grid.RowDefinitions>
                <Grid Margin="20,14,12,6">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
                  <TextBlock Text="检查明细" Style="{StaticResource PageTitle}" FontSize="22" VerticalAlignment="Center" />
                  <Button x:Name="BtnDetailsClose" Grid.Column="1" Content="收起" Style="{StaticResource GhostButton}" AutomationProperties.Name="收起检查明细" />
                </Grid>
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
                  <StackPanel Margin="20,4,18,16">
            <Grid Margin="0,0,0,8">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
              </Grid.ColumnDefinitions>
              <TextBlock Text="基础检查" Style="{StaticResource H2}" VerticalAlignment="Center" Margin="0,0,12,0" />
              <TextBlock x:Name="BasicStamp" Grid.Column="1" FontSize="13" Foreground="#CDB39B" TextWrapping="Wrap" VerticalAlignment="Center" Text="本次尚未检查" />
              <StackPanel x:Name="VerdictPanel" Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,0,0" Visibility="Collapsed">
                <TextBlock x:Name="VerdictText" FontSize="13" FontWeight="Bold" VerticalAlignment="Center" />
              </StackPanel>
            </Grid>
            <ItemsControl x:Name="Tiles" ItemTemplate="{StaticResource BasicTile}" Margin="-4,0,-4,6"><ItemsControl.ItemsPanel><ItemsPanelTemplate><UniformGrid Columns="3" /></ItemsPanelTemplate></ItemsControl.ItemsPanel></ItemsControl><Border Style="{StaticResource Card}" Margin="0,0,0,14">
              <StackPanel>
                <Grid Margin="16,10,10,8">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="检查明细" Style="{StaticResource H2}" VerticalAlignment="Center" />
                  <Button x:Name="BtnRecheck" Grid.Column="1" Style="{StaticResource GhostButton}">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Style="{StaticResource Icon}" Text="" FontSize="13" Margin="0,0,6,0" />
                      <TextBlock Text="重新检测" VerticalAlignment="Center" />
                    </StackPanel>
                  </Button>
                </Grid>
                <ItemsControl x:Name="Checks" ItemTemplate="{StaticResource CheckRow}" /></StackPanel>
            </Border>

            <Border x:Name="BaselineRow" Style="{StaticResource Card}" CornerRadius="10" Padding="16,6,8,6" Margin="0,0,0,14">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*" />
                  <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="BaselineText" FontSize="13" TextWrapping="Wrap" VerticalAlignment="Center" Text="星链 AS14593 · 允许 IP 变化，地区仅作展示。" />
                <Button x:Name="BtnBaseline" Grid.Column="1" Style="{StaticResource GhostButton}" Height="36" Margin="12,0,0,0" ToolTipService.ShowOnDisabled="True">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Style="{StaticResource Icon}" Text="" FontSize="13" Margin="0,0,6,0" />
                    <TextBlock Text="记录本次核验" VerticalAlignment="Center" />
                  </StackPanel>
                </Button>
              </Grid>
            </Border>

            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="*" />
              </Grid.ColumnDefinitions>
              <TextBlock Style="{StaticResource Icon}" Text="" Foreground="#CDB39B" VerticalAlignment="Top" Margin="0,3,8,0" />
              <TextBlock Grid.Column="1" FontSize="13" Foreground="#CDB39B" TextWrapping="Wrap" Text="先拥抱一下检查环境，再启动 Claude；动画结束不会自动启动。网络深度检测和设备特征用于排查，不作为基础启动条件。" />
            </Grid>
                  </StackPanel>
                </ScrollViewer>
              </Grid>
            </Border>
          </Grid>
        </TabItem>
        <TabItem><Border Style="{StaticResource GlassPanel}">
<Grid x:Name="PageAccounts" Margin="22,18,22,16">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
          </Grid.RowDefinitions>
          <Grid Grid.Row="0" Margin="0,0,0,14">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*" />
              <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            <WrapPanel VerticalAlignment="Center">
              <TextBlock Text="账号管理" Style="{StaticResource PageTitle}" />
              <TextBlock Text="点击卡片只会选中，确认后才会切换" Style="{StaticResource PageSub}" />
            </WrapPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,0,0">
              <Button x:Name="BtnRefresh" Style="{StaticResource GhostButton}" Height="40" FontSize="14" Margin="0,0,8,0">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Style="{StaticResource Icon}" Text="" Margin="0,0,6,0" />
                  <TextBlock Text="刷新" VerticalAlignment="Center" />
                </StackPanel>
              </Button>
              <Button x:Name="BtnShowAdd" Style="{StaticResource SecondaryButton}">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Style="{StaticResource Icon}" Text="" FontSize="12" Margin="0,0,6,0" />
                  <TextBlock Text="新增账号" VerticalAlignment="Center" />
                </StackPanel>
              </Button>
            </StackPanel>
          </Grid>

          <ListBox x:Name="AccountList" Grid.Row="2" Margin="-4,0,-4,0" Padding="4" Background="Transparent" BorderThickness="0" HorizontalContentAlignment="Stretch" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.CanContentScroll="False" ItemContainerStyle="{StaticResource AcctItem}" AutomationProperties.Name="账号列表" ItemTemplate="{StaticResource AccountCard}" />

          <Border x:Name="SwitchBar" Grid.Row="3" Style="{StaticResource Card}" Padding="16,12" Margin="0,14,0,0">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
              </Grid.ColumnDefinitions>
              <Grid VerticalAlignment="Center" Margin="0,0,16,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto" />
                  <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto" />
                  <RowDefinition Height="Auto" />
                </Grid.RowDefinitions>
                <TextBlock Text="已选中" FontSize="13" Foreground="#CDB39B" Margin="0,0,12,2" />
                <TextBlock x:Name="SelName" Grid.Column="1" FontSize="13" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,2" />
                <TextBlock Grid.Row="1" Text="正在使用" FontSize="13" Foreground="#CDB39B" Margin="0,0,12,0" />
                <TextBlock x:Name="CurName" Grid.Row="1" Grid.Column="1" FontSize="13" TextWrapping="Wrap" />
              </Grid>
              <Button x:Name="BtnSwitch" Grid.Column="1" Style="{StaticResource PrimaryButton}" Height="44" Padding="20,0" IsEnabled="False">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Style="{StaticResource Icon}" Text="" Margin="0,0,8,0" />
                  <TextBlock x:Name="SwitchLabel" Text="当前正在使用" VerticalAlignment="Center" />
                </StackPanel>
              </Button>
            </Grid>
          </Border>
        </Grid>
        </Border></TabItem>
        <TabItem><Border Style="{StaticResource GlassPanel}">
<ScrollViewer x:Name="PageNetwork" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
          <StackPanel Margin="22,18,22,16">
            <WrapPanel Margin="0,0,0,14">
              <TextBlock Text="网络检测" Style="{StaticResource PageTitle}" />
              <TextBlock Text="网络画像和协议探测分开保存，历史结果保留采集时间" Style="{StaticResource PageSub}" />
            </WrapPanel>

            <Border Style="{StaticResource Card}" Margin="0,0,0,14"><StackPanel>
              <TextBlock Text="FlClash 与 DNS 防护" Style="{StaticResource H2}" Margin="16,14,16,6"/>
              <TextBlock x:Name="FlClashSummary" Text="尚未检查 · 核对保存设置与生成配置，不连接检测网站" Foreground="#CDB39B" FontSize="12" TextWrapping="Wrap" Margin="16,0,16,10"/>
              <WrapPanel Margin="16,0,16,10">
                <Button x:Name="BtnFlClash" Content="检查 FlClash / DNS" Style="{StaticResource SecondaryButton}" Margin="0,0,8,6"/>
                <Button x:Name="BtnIpCheck" Content="IPCheck 深度 DNS" Style="{StaticResource GhostButton}" Height="40" Margin="0,0,8,6"/>
                <Button x:Name="BtnDnsBrowserLeaks" Content="Chrome 交叉复测" Style="{StaticResource GhostButton}" Height="40" Margin="0,0,8,6"/>
                <Button x:Name="BtnGuardMonitor" Content="实时监测" Style="{StaticResource GhostButton}" Height="40" Margin="0,0,0,6" AutomationProperties.Name="实时监测" ToolTip="查看常驻监测状态、提醒原因和重新检查入口"/>
              </WrapPanel>
              <Border x:Name="GuardPanel" Style="{StaticResource Card}" Margin="16,0,16,14" Padding="16" Visibility="Collapsed">
                <StackPanel>
                  <DockPanel LastChildFill="True">
                    <Button x:Name="BtnGuardClose" DockPanel.Dock="Right" Content="收起" Style="{StaticResource GhostButton}" Margin="8,0,0,0" AutomationProperties.Name="收起实时监测"/>
                    <TextBlock Text="实时监测" Style="{StaticResource H2}" VerticalAlignment="Center"/>
                  </DockPanel>
                  <Border x:Name="GuardStatusPanel" CornerRadius="10" Background="#26F1D5B4" Padding="14" Margin="0,12,0,12">
                    <StackPanel>
                      <TextBlock x:Name="GuardTitle" Text="正在启动守护" FontSize="18" FontWeight="Bold" Foreground="#FFD89A" TextWrapping="Wrap"/>
                      <TextBlock x:Name="GuardSummary" Text="正在读取后台状态。" FontSize="13" Foreground="#EBD4BE" TextWrapping="Wrap" Margin="0,6,0,0" AutomationProperties.LiveSetting="Polite"/>
                      <TextBlock x:Name="GuardStamp" Text="本次完整核验尚未完成" FontSize="12" Foreground="#CDB39B" TextWrapping="Wrap" Margin="0,8,0,0"/>
                      <Button x:Name="BtnGuardCheck" Content="立即重新检查" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Left" Margin="0,12,0,0" IsEnabled="False"/>
                    </StackPanel>
                  </Border>
                  <TextBlock Text="网络异常只弹窗提醒，每 1 分钟重复一次，恢复后停止。不会结束、重启或锁住 Claude / Claude Code。" FontSize="12" Foreground="#CDB39B" TextWrapping="Wrap"/>
                  <Expander Header="监测范围与运行方式" Margin="0,10,0,0">
                    <StackPanel Margin="0,8,0,0">
                      <TextBlock Text="代理内核、TUN、本地代理端口、DNS 防护配置、Starlink AS14593 归属，以及同轮同地址族的出口一致性。" FontSize="12" Foreground="#CDB39B" TextWrapping="Wrap" Margin="0,0,0,8"/>
                      <TextBlock Text="覆盖 15 个固定域名，并补充本机 DNS 缓存中发现的 Claude 相关子域名。部分资源域名只能核对分流规则；DNS 配置核对不等于浏览器泄露测试。" FontSize="12" Foreground="#CDB39B" TextWrapping="Wrap" Margin="0,0,0,8"/>
                      <TextBlock Text="登录自启，关闭窗口收起到托盘。本地每轮后等待 2 秒；HTTPS 每轮最多 60 秒。正常结果后等待 60 秒，首次异常 5 秒后复查，证据不足 15 秒后重查。检测存在间隔。" FontSize="12" Foreground="#CDB39B" TextWrapping="Wrap"/>
                    </StackPanel>
                  </Expander>
                </StackPanel>
              </Border>
              <Expander Header="检查结果" Margin="16,0,16,10" IsExpanded="True"><ItemsControl x:Name="FlClashChecks" ItemTemplate="{StaticResource CheckRow}"/></Expander>
              <Expander Header="升级后怎么检查、怎么修复" Margin="16,0,16,14"><StackPanel Margin="0,10,0,0">
                <TextBlock Text="1. 先备份。升级或切换订阅后，核对当前配置、节点选择和已有固定出口脚本；脚本模式下要真正选中脚本。" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,8"/>
                <TextBlock Text="2. FlClash 0.9.1：工具 → 进阶配置 → 网络 → 添加覆写项 → 严格路由，再打开开关。只改保存值、未选覆写项，可能仍随订阅。" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,8"/>
                <TextBlock Text="3. DNS 逐项覆写优先于脚本。若已有脚本负责主 DNS，核对 Nameserver / Fallback 是否仍被全局覆写。直连专用 DNS 可添加 Direct Nameserver 覆写并清空，让它继承主解析流程。" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,8"/>
                <TextBlock Text="4. 国内网站策略、节点域名解析和引导 DNS 分开检查，避免代理与 DNS 循环依赖。any:53 默认只覆盖 UDP；TCP 和局域网 DNS 旁路需要单独复测。" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,8"/>
                <TextBlock Text="5. 在助手内运行 IPCheck 深度 DNS，首次需登录原站；也可在 Chrome 用 BrowserLeaks 交叉复测。两种浏览器的 DNS 设置可能不同。关注意外解析器与 ECS；数量多不等于泄露，打开网页不会自动记为通过。" TextWrapping="Wrap" FontSize="12" Margin="0,0,0,8"/>
                <TextBlock Text="应用设置后重新检查，重启 FlClash 后再测一次。严格路由不是客户端退出后的永久断网开关；代理掉线保护需单独验证。" TextWrapping="Wrap" FontSize="12" Foreground="#FFD89A"/>
              </StackPanel></Expander>
            </StackPanel></Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,14">
              <StackPanel>
                <Grid Margin="16,14,16,10">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                  </Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,12,0">
                    <TextBlock Text="网络画像" Style="{StaticResource H2}" />
                    <TextBlock x:Name="InsightTitle" FontSize="12" Foreground="#CDB39B" TextWrapping="Wrap" Text="网络画像" />
                  </StackPanel>
                  <Button x:Name="BtnNetwork" Grid.Column="1" Style="{StaticResource SecondaryButton}">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Style="{StaticResource Icon}" Text="" Margin="0,0,6,0" />
                      <TextBlock Text="检测网络画像" VerticalAlignment="Center" />
                    </StackPanel>
                  </Button>
                </Grid>
                <TextBlock x:Name="InsightSummary" Margin="16,0,16,10" FontSize="13" TextWrapping="Wrap" Visibility="Visible" Text="尚未检测 · 多来源出口、DNS 路径与 IP 信誉" />
                <StackPanel Margin="16,4,16,12">
     <ItemsControl x:Name="InsightMetrics" ItemTemplate="{StaticResource MetricCard}" ItemsPanel="{StaticResource MetricPanel}" Margin="-4,4,-4,12" />
     <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
      <TextBox x:Name="InsightSearch" ToolTip="搜索名称、结果、来源及测量细节" AutomationProperties.Name="搜索检测结果" Padding="10,0" />
      <TextBlock Text="搜索名称、内容、来源…" Foreground="#A88E78" IsHitTestVisible="False" Margin="12,0" VerticalAlignment="Center"><TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed" /><Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=InsightSearch}" Value=""><Setter Property="Visibility" Value="Visible" /></DataTrigger></Style.Triggers></Style></TextBlock.Style></TextBlock>
      <CheckBox x:Name="InsightAttention" Grid.Column="1" Content="只看待核对 / 未验证" FontSize="12" Foreground="#CDB39B" Margin="12,0,0,0" VerticalAlignment="Center" />
     </Grid>
     <Border x:Name="InsightEmpty" Background="#1AFFE9CC" CornerRadius="8" Padding="18" Margin="0,12,0,0"><TextBlock x:Name="InsightEmptyText" Text="尚未检测。点击上方按钮开始。" Foreground="#CDB39B" TextWrapping="Wrap" TextAlignment="Center" /></Border>
    </StackPanel>
<Border Style="{StaticResource Card}" Padding="16" Margin="0,0,0,14"><StackPanel>
 <TextBlock Text="Claude 连通性与网络出口" Style="{StaticResource H2}"/>
 <TextBlock x:Name="AddressStamp" Text="尚未检测 · 点击网络画像的开始按钮" Foreground="#CDB39B" FontSize="12" Margin="0,6,0,12" TextWrapping="Wrap"/>
 <ItemsControl x:Name="ClaudeEndpoints" ItemTemplate="{StaticResource AddressCard}"><ItemsControl.ItemsPanel><ItemsPanelTemplate><UniformGrid Columns="2"/></ItemsPanelTemplate></ItemsControl.ItemsPanel></ItemsControl>
 <TextBlock Text="DNS 解析器与归属" Style="{StaticResource H2}" Margin="0,12,0,0"/>
 <TextBlock x:Name="DnsHeadline" Text="尚未检测 · 按服务与路径展示解析器，不按国家判安全" Foreground="#CDB39B" FontSize="12" Margin="0,6,0,12" TextWrapping="Wrap"/>
 <Expander x:Name="DnsAddressExpander" Header="展开解析器地址、国家 / 城市与组织" Foreground="#F1C296" FontSize="13"><ItemsControl x:Name="DnsResolvers" ItemTemplate="{StaticResource AddressCard}" Margin="0,12,0,0"/></Expander>
</StackPanel></Border>
<ItemsControl x:Name="InsightGroups" ItemTemplate="{StaticResource CheckGroup}" /></StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,14">
              <StackPanel>
                <Grid Margin="16,14,16,10">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                  </Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,12,0">
                    <TextBlock Text="WebRTC 与协议泄漏检测" Style="{StaticResource H2}" />
                    <TextBlock x:Name="DeepStamp" FontSize="12" Foreground="#CDB39B" TextWrapping="Wrap" Text="尚未检测 · IPv6 / UDP / WebRTC" />
                  </StackPanel>
                  <Button x:Name="BtnDeep" Grid.Column="1" Style="{StaticResource SecondaryButton}">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Style="{StaticResource Icon}" Text="" Margin="0,0,6,0" />
                      <TextBlock Text="开始深度检测" VerticalAlignment="Center" />
                    </StackPanel>
                  </Button>
                </Grid>
                <Border Background="#1AFFE9CC" CornerRadius="8" Padding="14" Margin="16,0,16,12"><StackPanel><TextBlock Text="WebRTC 隐私暴露检查" FontWeight="Bold" FontSize="13"/><TextBlock x:Name="WebRtcSummary" Text="未验证 · 尚未运行。没有候选地址或 STUN 无响应均不能证明没有泄漏。" Foreground="#CDB39B" FontSize="13" TextWrapping="Wrap" Margin="0,5,0,0"/></StackPanel></Border>
<ItemsControl x:Name="DeepChecks" ItemTemplate="{StaticResource CheckRow}" /></StackPanel>
            </Border>

            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="*" />
              </Grid.ColumnDefinitions>
              <TextBlock Style="{StaticResource Icon}" Text="" Foreground="#CDB39B" VerticalAlignment="Top" Margin="0,3,8,0" />
              <TextBlock Grid.Column="1" FontSize="13" Foreground="#CDB39B" TextWrapping="Wrap" Text="基础检查通过后解锁启动，后台会在打开 Claude 前再核验。这里的网络画像和协议探测用于排查，不改变代理连接。" />
            </Grid>
          </StackPanel>
        </ScrollViewer>
        </Border></TabItem>
        <TabItem><Border Style="{StaticResource GlassPanel}">
<ScrollViewer x:Name="PageFingerprint" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
          <StackPanel Margin="22,18,22,16">
            <WrapPanel Margin="0,0,0,14">
              <TextBlock Text="设备特征" Style="{StaticResource PageTitle}" />
              <TextBlock Text="来源：本地独立 Edge。全局一份基准，不按账号区分" Style="{StaticResource PageSub}" />
            </WrapPanel>

            <Border Style="{StaticResource Card}" Padding="20,16" Margin="0,0,0,14">
              <Grid>
                <Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="Auto" /></Grid.RowDefinitions><Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto" />
                  <ColumnDefinition Width="*" />
                  <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <Grid x:Name="FpIconBox" Width="36" Height="36" VerticalAlignment="Top" Margin="0,0,12,0"><Border Background="#26E1B383" CornerRadius="18"><TextBlock Text="" Style="{StaticResource Icon}" Foreground="#F1C296" HorizontalAlignment="Center" FontSize="20" /></Border></Grid>
                <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="0,0,16,0">
                  <TextBlock x:Name="FingerprintTitle" FontSize="18" FontWeight="Bold" TextWrapping="Wrap" Text="设备特征 · 尚未采集" />
                  <TextBlock x:Name="FingerprintVerdict" FontSize="13" Foreground="#CDB39B" TextWrapping="Wrap" Margin="0,2,0,0" Text="20 项本地特征 · 使用独立临时 Edge" />
                  <TextBlock x:Name="FingerprintTime" FontSize="12" Foreground="#CDB39B" TextWrapping="Wrap" Margin="0,4,0,0" Text="20 项指纹基准不会自动覆盖；另显示 4 项区域信息并忽略影响。" />
                </StackPanel>
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Grid.Row="1" Grid.ColumnSpan="3" Margin="0,16,0,0">
                  <Button x:Name="BtnFingerprint" Style="{StaticResource PrimaryButton}" Height="44" Margin="0,0,10,0">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Style="{StaticResource Icon}" Text="" Margin="0,0,8,0" />
                      <TextBlock Text="检测设备特征" VerticalAlignment="Center" />
                    </StackPanel>
                  </Button>
                  <Button x:Name="BtnFingerprintSave" Style="{StaticResource SecondaryButton}" Height="44" Content="采集并记住基准" />
                </StackPanel>
              </Grid>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,14"><StackPanel><TextBlock Text="字体与 Emoji" Style="{StaticResource H2}" Margin="16,12,16,8"/><TextBlock Text="实际字体测量和 Emoji 像素采样，不按中文字体或系统品牌打风险分。" Foreground="#CDB39B" FontSize="12" TextWrapping="Wrap" Margin="16,0,16,10"/><ItemsControl x:Name="FingerprintSpotlight" ItemTemplate="{StaticResource CheckRow}"/></StackPanel></Border>
<Border Style="{StaticResource Card}" Margin="0,0,0,14"><StackPanel><TextBlock Text="时区与语言 · 忽略影响" Style="{StaticResource H2}" Margin="16,12,16,8"/><TextBlock x:Name="RegionalNote" Text="采集后显示，不参与风险评分、指纹基准或启动判断。" Foreground="#CDB39B" FontSize="12" TextWrapping="Wrap" Margin="16,0,16,10"/><ItemsControl x:Name="RegionalChecks" ItemTemplate="{StaticResource CheckRow}"/><Button x:Name="BtnGoEnvironment" Content="管理系统环境设置 →" Style="{StaticResource GhostButton}" HorizontalAlignment="Left" Margin="16,4,0,12"/></StackPanel></Border>
<Border x:Name="FpDiffCard" Style="{StaticResource Card}" Margin="0,0,0,14" Visibility="Collapsed">
              <StackPanel>
                <Grid Margin="16,12,16,8">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="变化项" Style="{StaticResource H2}" />
                  <TextBlock x:Name="FpDiffCount" Grid.Column="1" FontSize="12" Foreground="#CDB39B" VerticalAlignment="Center" />
                </Grid>
                <ItemsControl x:Name="FpDiff" ItemTemplate="{StaticResource CheckRow}" /></StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,14">
              <StackPanel>
                <Grid Margin="16,12,16,8">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="采样详情" Style="{StaticResource H2}" />
                  <TextBlock Grid.Column="1" Text="20 项本地特征" FontSize="12" Foreground="#CDB39B" VerticalAlignment="Center" />
                </Grid>
                <TextBlock x:Name="FingerprintSummary" Foreground="#CDB39B" FontSize="12" TextWrapping="Wrap" Margin="16,0,16,8" /><StackPanel Margin="16,4,16,12">
     <ItemsControl x:Name="FingerprintMetrics" ItemTemplate="{StaticResource MetricCard}" ItemsPanel="{StaticResource MetricPanel}" Margin="-4,4,-4,12" />
     <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
      <TextBox x:Name="FingerprintSearch" ToolTip="搜索名称、结果、来源及测量细节" AutomationProperties.Name="搜索检测结果" Padding="10,0" />
      <TextBlock Text="搜索名称、内容、来源…" Foreground="#A88E78" IsHitTestVisible="False" Margin="12,0" VerticalAlignment="Center"><TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed" /><Style.Triggers><DataTrigger Binding="{Binding Text, ElementName=FingerprintSearch}" Value=""><Setter Property="Visibility" Value="Visible" /></DataTrigger></Style.Triggers></Style></TextBlock.Style></TextBlock>
      <CheckBox x:Name="FingerprintAttention" Grid.Column="1" Content="只看待核对 / 未验证" FontSize="12" Foreground="#CDB39B" Margin="12,0,0,0" VerticalAlignment="Center" />
     </Grid>
     <Border x:Name="FingerprintEmpty" Background="#1AFFE9CC" CornerRadius="8" Padding="18" Margin="0,12,0,0"><TextBlock x:Name="FingerprintEmptyText" Text="尚未检测。点击上方按钮开始。" Foreground="#CDB39B" TextWrapping="Wrap" TextAlignment="Center" /></Border>
    </StackPanel><ItemsControl x:Name="FingerprintGroups" ItemTemplate="{StaticResource CheckGroup}" /></StackPanel>
            </Border>

            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="*" />
              </Grid.ColumnDefinitions>
              <TextBlock Style="{StaticResource Icon}" Text="" Foreground="#CDB39B" VerticalAlignment="Top" Margin="0,3,8,0" />
              <TextBlock Grid.Column="1" FontSize="13" Foreground="#CDB39B" TextWrapping="Wrap" Text="时区、语言、区域格式与 UTC 偏移仅展示，忽略其影响。字体和 Emoji 不用于地区风险评分，设备特征不参与启动判断。" />
            </Grid>
          </StackPanel>
        </ScrollViewer>
        </Border></TabItem>
        <TabItem><Border Style="{StaticResource GlassPanel}">
<Grid Margin="22,18,22,16"><Grid.RowDefinitions><RowDefinition Height="Auto" /><RowDefinition Height="Auto" /><RowDefinition Height="*" /></Grid.RowDefinitions>
     <StackPanel><TextBlock Text="诊断记录" Style="{StaticResource PageTitle}" Margin="0,4,0,8" />
      <TextBlock Text="按时间查看结果，与上一次同类检测比较。IP 用摘要显示；记录仍包含设备和网络归属信息，可预览后导出给别人分析。" Foreground="#C9AE95" TextWrapping="Wrap" Margin="0,0,0,16" />
     </StackPanel>
     <Grid Grid.Row="1" Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" /><ColumnDefinition Width="Auto" /></Grid.ColumnDefinitions>
      <ComboBox x:Name="ReportList" DisplayMemberPath="Label" Padding="8" Margin="0,0,12,0" />
      <Button x:Name="BtnReports" Grid.Column="1" Content="刷新记录" /><Button x:Name="BtnExport" Grid.Column="2" Content="导出报告" Margin="0" />
     </Grid>
     <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel>
      <Border Background="#1FE1B383" CornerRadius="10" Padding="14" Margin="0,0,0,14"><TextBlock x:Name="ReportComparison" Text="尚无记录。完成检测后会自动保存。" TextWrapping="Wrap" /></Border>
      <ItemsControl x:Name="ReportGroups" ItemTemplate="{StaticResource CheckGroup}" />
     </StackPanel></ScrollViewer>
    </Grid>
        </Border></TabItem>
        <TabItem><Border Style="{StaticResource GlassPanel}">
<ScrollViewer x:Name="PageAbout" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
          <StackPanel Margin="22,18,22,20">
            <WrapPanel Margin="0,0,0,14">
              <TextBlock Text="说明" Style="{StaticResource PageTitle}" />
              <TextBlock Text="各项检测的范围与限制，以及本地数据的位置" Style="{StaticResource PageSub}" />
            </WrapPanel>

            <Border Style="{StaticResource Card}" Padding="20,16" Margin="0,0,0,14">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <Border Width="36" Height="36" CornerRadius="10" Background="#45352E" BorderBrush="#4DFFE1B5" BorderThickness="1"><TextBlock Text="✳" FontFamily="Segoe UI Symbol" FontSize="20" Foreground="#E3AE83" HorizontalAlignment="Center" VerticalAlignment="Center" /></Border>
                  <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="Claude 启动助手" FontSize="16" FontWeight="Bold" />
                    <TextBlock Text="版本 1.1.0 · Windows" FontSize="13" Foreground="#CDB39B" />
                  </StackPanel>
                </StackPanel>
                <Border BorderBrush="#26F1D5B4" BorderThickness="0,1,0,0" Margin="0,14,0,0" Padding="0,12,0,0">
                  <StackPanel x:Name="BoundaryList"><TextBlock Text="概览页的「拥抱一下」会运行基础检查，同时播放 10 秒夕照拥抱动画；「启动 Claude」单独启动、不播放特效，动画结束也不会自动启动。系统关闭了动画效果或无法播放视频时，直接显示最后一帧。动画素材位于程序目录的 assets\hug。" TextWrapping="Wrap" Margin="0,0,0,12" FontSize="13" Foreground="#CDB39B" />
      <TextBlock Text="登录 Windows 后自动启动网络监测。发现代理中断、出口变化、非星链或 DNS 配置异常时，弹出独立提示窗；异常持续时每分钟再次提醒，关闭提示窗也不会停止监测。不会结束、重启或锁定 Claude / Claude Code。" TextWrapping="Wrap" Margin="0,0,0,12" FontSize="13" Foreground="#CDB39B" />
      <TextBlock Text="深度检测比较 HTTPS、IPv6、UDP / STUN 和独立 Edge 浏览器 WebRTC 的实际出口。它不申请摄像头或麦克风权限，不修改网络、关闭 Claude 或改变现有浏览器。超时、无响应或缺少对照时会显示未验证。" TextWrapping="Wrap" Margin="0,0,0,12" FontSize="13" Foreground="#CDB39B" />
      <TextBlock Text="超时、限流、证据不足和内部错误显示「检测受限」，不会冒充已经确认的泄露。睡眠恢复和配置变化触发重新核验；检测恢复正常后自动停止提醒。最近结果超过 3 分钟不再显示为当前通过。匿名探测不代表登录或模型请求。" TextWrapping="Wrap" Margin="0,0,0,12" FontSize="13" Foreground="#CDB39B" />
      <TextBlock Text="基础检查覆盖 15 个固定域名，以及 DNS 缓存中发现的 6 类 Claude / Anthropic 域名子域。每个目标检查显式代理与系统 / TUN 路径；能返回出口的目标核验 AS14593 和同地址族一致性，部分资源域名仅核对与 API 相同的分流规则，界面单独标记。DNS 防护属于配置证据，不是全部 DNS 流量证明。网络检测的第四个「实时监测」入口可以查看监测状态并重新检查。" TextWrapping="Wrap" Margin="0,0,0,12" FontSize="13" Foreground="#CDB39B" />
      <TextBlock Text="日常检测与启动无需管理员权限，手动环境设置受 Windows 权限和策略限制。运行 install.ps1 可选创建桌面快捷方式。此版本基于 YOURSJEYO/claude-switcher 的 MIT 源码适配。" TextWrapping="Wrap" FontSize="13" Foreground="#CDB39B" Margin="0,0,0,12" />
     </StackPanel>
                </Border>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,14">
              <StackPanel>
                <TextBlock Text="数据与恢复" Style="{StaticResource H2}" Margin="16,12,16,8" />
                <Border BorderBrush="#26F1D5B4" BorderThickness="0,1,0,0" Padding="16,12">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*" />
                      <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <StackPanel VerticalAlignment="Center">
                      <TextBlock Text="状态目录" FontSize="13" Foreground="#CDB39B" />
                      <TextBlock FontFamily="Consolas, Microsoft YaHei UI" FontSize="13" TextWrapping="Wrap" Text="" x:Name="StateRootText" />
                    </StackPanel>
                    <Button x:Name="BtnFolder" Grid.Column="1" Style="{StaticResource OutlineButton}" Margin="12,0,0,0">
                      <StackPanel Orientation="Horizontal">
                        <TextBlock Style="{StaticResource Icon}" Text="" Margin="0,0,8,0" />
                        <TextBlock Text="打开状态目录" VerticalAlignment="Center" />
                      </StackPanel>
                    </Button>
                  </Grid>
                </Border>
                <Border BorderBrush="#26F1D5B4" BorderThickness="0,1,0,0" Padding="16,12,16,14">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*" />
                      <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <StackPanel VerticalAlignment="Center">
                      <TextBlock Text="恢复" FontWeight="Bold" />
                      <TextBlock Text="仅在切换中断或本地数据异常时使用。恢复会替换应用数据，开始前会单独确认。" FontSize="13" Foreground="#CDB39B" TextWrapping="Wrap" Margin="0,2,0,0" />
                    </StackPanel>
                    <Button x:Name="BtnRestore" Grid.Column="1" Style="{StaticResource OutlineDangerButton}" Margin="12,0,0,0">
                      <StackPanel Orientation="Horizontal">
                        <TextBlock Style="{StaticResource Icon}" Text="" Margin="0,0,8,0" />
                        <TextBlock Text="恢复…" VerticalAlignment="Center" />
                      </StackPanel>
                    </Button>
                  </Grid>
                </Border>
                </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Padding="16,12,16,6" Margin="0,0,0,14">
              <StackPanel>
                <TextBlock Text="状态说明" Style="{StaticResource H2}" Margin="0,0,0,10" />
                <TextBlock FontSize="13" Foreground="#CDB39B" TextWrapping="Wrap" LineHeight="23" Text="已核对：本项检查完成。需处理：检测失败或发现明确差异。请核对：需要人工确认。未验证：缺少证据或请求未完成。信息：说明范围，不表示通过。" /></StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="检测覆盖范围" Style="{StaticResource H2}" Margin="16,12,16,8" />
                <TextBlock Margin="16,0,16,16" Foreground="#CDB39B" FontSize="13" TextWrapping="Wrap" LineHeight="23" Text="基础启动：Claude、代理内核、TUN、监听端口、FlClash / DNS 配置与星链出口。网络诊断：多来源出口、IPv6、Claude 相关域名、4 家 DNS、IP 信誉、服务状态。协议探测：UDP / STUN 与独立 Edge WebRTC。设备特征：20 项摘要与基准比较。历史：按时间保存、比较和导出。" /></StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
        </Border></TabItem>
        <TabItem><Border Style="{StaticResource GlassPanel}">
<ScrollViewer x:Name="PageEnvironment" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel Margin="22,18,22,16">
 <DockPanel Margin="0,0,0,14"><Button x:Name="BtnEnvironmentRead" Content="读取当前设置" DockPanel.Dock="Right" Style="{StaticResource SecondaryButton}"/><TextBlock Text="环境设置" Style="{StaticResource PageTitle}"/></DockPanel>
 <TextBlock Text="管理系统时区、区域格式，以及 Chrome 的网页语言和字体。修改后在同一个 Chrome 配置文件中复测。" Style="{StaticResource PageSub}" Margin="0,0,0,14"/>
 <Border Style="{StaticResource Card}" Padding="18" Margin="0,0,0,14"><StackPanel>
  <TextBlock Text="Chrome / IPPure 网页环境" Style="{StaticResource H2}"/>
  <TextBlock Text="这里打开 Chrome 自身的设置，实际修改由 Chrome 保存。IPPure 的分数是第三方估计，不作为助手的启动条件。" Foreground="#CDB39B" TextWrapping="Wrap" FontSize="13" Margin="0,6,0,12"/>
  <TextBlock Text="语言：在 Chrome 的“首选语言”中添加、排序或移除语言。网页读取的是这份列表；仅调整 Windows 语言顺序可能不会改变它。" TextWrapping="Wrap" FontSize="13" Margin="0,0,0,10"/>
  <TextBlock Text="字体：可修改标准、衬线、无衬线和等宽字体。网页指定的字体仍可能优先生效；换默认字体后，已安装的中文字体仍可被探测到。" TextWrapping="Wrap" FontSize="13" Margin="0,0,0,10"/>
  <TextBlock Text="Emoji：IPPure 的 Microsoft style 表示识别到了 Windows，不代表渲染故障。实际样式由系统和网页字体决定，Chrome 的字体设置不能切换操作系统身份。" Foreground="#CDB39B" TextWrapping="Wrap" FontSize="13" Margin="0,0,0,12"/>
  <WrapPanel>
   <Button x:Name="BtnChromeLanguages" Tag="Languages" Content="修改 Chrome 语言" Margin="0,0,10,8"/>
   <Button x:Name="BtnChromeFonts" Tag="Fonts" Content="修改 Chrome 字体" Margin="0,0,10,8"/>
   <Button x:Name="BtnChromeIpPure" Tag="IpPure" Content="在 Chrome 复测 IPPure" Style="{StaticResource SecondaryButton}" Margin="0,0,0,8"/>
  </WrapPanel>
  <TextBlock x:Name="ChromeEnvironmentFeedback" Text="Chrome 时区沿用系统设置，可在下方调整。打开检测页后等待结果；需要时点“重新扫描”。" Foreground="#F1C296" TextWrapping="Wrap" FontSize="12" Margin="0,4,0,0"/>
 </StackPanel></Border>
 <Border Style="{StaticResource Card}" Padding="18" Margin="0,0,0,14"><StackPanel><TextBlock Text="系统时区" Style="{StaticResource H2}"/><TextBlock x:Name="TimezoneCurrent" Text="尚未读取" Foreground="#CDB39B" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,12"/><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><ComboBox x:Name="TimezoneChoice" IsEnabled="False" DisplayMemberPath="Label" SelectedValuePath="Id" Padding="10,8"/><Button x:Name="BtnTimezoneApply" IsEnabled="False" Grid.Column="1" Content="应用时区" Margin="12,0,0,0"/></Grid><TextBlock Text="修改整个系统的时区，UTC 偏移随时区与夏令时自动变化。系统策略可能限制修改权限。" Foreground="#CDB39B" TextWrapping="Wrap" FontSize="12" Margin="0,10,0,0"/></StackPanel></Border>
 <Border Style="{StaticResource Card}" Padding="18" Margin="0,0,0,14"><StackPanel><TextBlock Text="区域格式" Style="{StaticResource H2}"/><TextBlock x:Name="FormatCurrent" Text="尚未读取" Foreground="#CDB39B" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,12"/><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><ComboBox x:Name="FormatChoice" IsEnabled="False" DisplayMemberPath="Label" SelectedValuePath="Id" IsTextSearchEnabled="True" Padding="10,8"/><Button x:Name="BtnFormatApply" IsEnabled="False" Grid.Column="1" Content="应用格式" Margin="12,0,0,0"/></Grid><TextBlock Text="改变当前 Windows 用户的日期、数字等区域格式。浏览器自有语言设置仍可能覆盖 Intl 的实际结果。" Foreground="#CDB39B" TextWrapping="Wrap" FontSize="12" Margin="0,10,0,0"/></StackPanel></Border>
 <Border Style="{StaticResource Card}" Padding="18" Margin="0,0,0,14"><StackPanel><TextBlock Text="首选语言顺序" Style="{StaticResource H2}"/><TextBlock x:Name="LanguageCurrent" Text="尚未读取" Foreground="#CDB39B" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,12"/><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><ComboBox x:Name="LanguageChoice" IsEnabled="False" DisplayMemberPath="Label" SelectedValuePath="Id" Padding="10,8"/><Button x:Name="BtnLanguageApply" IsEnabled="False" Grid.Column="1" Content="设为首选" Margin="12,0,0,0"/></Grid><TextBlock Text="仅将已配置语言移到第一位，保留其他语言及输入法。采用系统语言偏好的应用可能在下次打开时变化；应用内语言仍由各自设置决定。" Foreground="#CDB39B" TextWrapping="Wrap" FontSize="12" Margin="0,10,0,0"/></StackPanel></Border>
 <Border Style="{StaticResource Card}" Padding="18"><StackPanel><TextBlock Text="语言包、显示语言与自动时区" Style="{StaticResource H2}"/><TextBlock Text="需要添加语言、安装语言包、选择 Windows 显示语言或管理自动时区时，打开系统设置。应用本页设置前会显示变更摘要，并保存原设置记录。" Foreground="#CDB39B" TextWrapping="Wrap" FontSize="13" Margin="0,6,0,12"/><WrapPanel><Button x:Name="BtnWindowsLanguage" Content="Windows 语言设置" Margin="0,0,10,8"/><Button x:Name="BtnWindowsTime" Content="Windows 日期与时间" Margin="0,0,10,8"/></WrapPanel><TextBlock x:Name="EnvironmentFeedback" Text="尚未修改任何设置。" Foreground="#F1C296" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,0"/></StackPanel></Border>
</StackPanel></ScrollViewer>
        </Border></TabItem>
      </TabControl>

      <Border x:Name="Sidebar" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="22,22,22,0" Padding="5" CornerRadius="9" BorderBrush="#48F5D6AD" BorderThickness="1" Tag="Glass">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#9934241D" Offset="0" /><GradientStop Color="#803E2D21" Offset="1" /></LinearGradientBrush>
        </Border.Background>
        <StackPanel Orientation="Horizontal">
          <StackPanel Orientation="Horizontal" Margin="10,0,12,0" VerticalAlignment="Center">
            <TextBlock Text="✳" FontFamily="Segoe UI Symbol" FontSize="22" Foreground="#E3AE83" VerticalAlignment="Center" />
            <TextBlock x:Name="BrandText" Text="Claude" FontFamily="Georgia" FontSize="22" Foreground="#FFF0DC" VerticalAlignment="Center" Margin="7,0,0,0" />
          </StackPanel>
          <RadioButton x:Name="NavOverview" GroupName="Nav" Style="{StaticResource NavPill}" Tag="⌂" ToolTip="概览" AutomationProperties.Name="概览" IsChecked="True"><TextBlock x:Name="NavOverviewText" Text="概览" /></RadioButton>
          <RadioButton x:Name="NavNetwork" GroupName="Nav" Style="{StaticResource NavPill}" Tag="◎" ToolTip="网络检测" AutomationProperties.Name="网络检测"><TextBlock x:Name="NavNetworkText" Text="网络检测" /></RadioButton>
          <RadioButton x:Name="NavFingerprint" GroupName="Nav" Style="{StaticResource NavPill}" Tag="▣" ToolTip="设备特征" AutomationProperties.Name="设备特征"><TextBlock x:Name="NavFingerprintText" Text="设备特征" /></RadioButton>
          <RadioButton x:Name="NavAccounts" GroupName="Nav" Style="{StaticResource NavPill}" Tag="◫" ToolTip="账号管理" AutomationProperties.Name="账号管理"><TextBlock x:Name="NavAccountsText" Text="账号管理" /></RadioButton>
          <RadioButton x:Name="NavReports" GroupName="Nav" Style="{StaticResource NavPill}" Tag="≡" ToolTip="诊断记录" AutomationProperties.Name="诊断记录"><TextBlock x:Name="NavReportsText" Text="诊断记录" /></RadioButton>
          <RadioButton x:Name="NavEnvironment" GroupName="Nav" Style="{StaticResource NavPill}" Tag="⚙" ToolTip="环境设置" AutomationProperties.Name="环境设置"><TextBlock x:Name="NavEnvironmentText" Text="环境设置" /></RadioButton>
          <RadioButton x:Name="NavAbout" GroupName="Nav" Style="{StaticResource NavPill}" Tag="ⓘ" ToolTip="说明" AutomationProperties.Name="说明"><TextBlock x:Name="NavAboutText" Text="说明" /></RadioButton>
        </StackPanel>
      </Border>
    </Grid>

    <Border x:Name="StatusBar" Grid.Row="1" Background="#45352E" BorderBrush="#6E5240" BorderThickness="0,1,0,0" MinHeight="32">
      <Grid>
        <ProgressBar x:Name="BusyBar" Height="2" VerticalAlignment="Top" Margin="0,-1,0,0" IsIndeterminate="True" Foreground="#E1B383" Background="#33E1B383" BorderThickness="0" Visibility="Collapsed" />
        <Grid Margin="16,8,16,8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto" /><ColumnDefinition Width="*" /></Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Top" MaxWidth="440">
            <Ellipse Width="5" Height="5" Fill="#DDB489" VerticalAlignment="Center" Margin="0,0,8,0" />
            <TextBlock x:Name="StatusText" Text="就绪 · 请先拥抱一下，检查环境" FontSize="12" Foreground="#F0DFC9" TextWrapping="Wrap" />
          </StackPanel>
          <TextBlock x:Name="Hint" Grid.Column="1" Text="基础检查通过后才能启动 Claude。" FontSize="11" Foreground="#CBB098" TextWrapping="Wrap" TextAlignment="Right" HorizontalAlignment="Right" Margin="24,1,0,0" />
        </Grid>
      </Grid>
    </Border>

    <Grid x:Name="DialogHost" Grid.RowSpan="2" Background="#99140E0B" Visibility="Collapsed">
      <Border x:Name="DialogBox" Width="420" CornerRadius="14" Margin="24" Padding="24,22,24,20" HorizontalAlignment="Center" VerticalAlignment="Center" BorderBrush="#4DFFE1B5" BorderThickness="1" KeyboardNavigation.TabNavigation="Cycle" KeyboardNavigation.DirectionalNavigation="Contained">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#F52E211A" Offset="0" /><GradientStop Color="#EE3E2D21" Offset="1" /></LinearGradientBrush>
        </Border.Background>
        <Border.Effect>
          <DropShadowEffect BlurRadius="40" ShadowDepth="12" Direction="270" Opacity="0.45" Color="#000000" />
        </Border.Effect>
        <StackPanel>
          <TextBlock x:Name="DialogTitle" FontFamily="{StaticResource SerifFont}" FontSize="21" Foreground="#FFF1DB" TextWrapping="Wrap" />
          <TextBlock x:Name="DialogDesc" Margin="0,8,0,0" FontSize="13" Foreground="#CDB39B" TextWrapping="Wrap" Text="名称仅用于本地账号管理，不修改登录资料。" />
          <StackPanel x:Name="DialogForm" Margin="0,16,0,0" Visibility="Visible">
            <TextBlock Text="账号名称" FontSize="13" Foreground="#CDB39B" />
            <TextBox x:Name="AccountName" Style="{StaticResource Field}" Margin="0,6,0,0" AutomationProperties.Name="账号名称" MaxLength="32" />
            <TextBlock x:Name="DialogError" Margin="0,6,0,0" FontSize="12" Foreground="#FFB4A6" TextWrapping="Wrap" Visibility="Collapsed" />
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
            <Button x:Name="DialogCancel" Content="取消" Style="{StaticResource OutlineButton}" Margin="0,0,8,0" />
            <Button x:Name="BtnAdd" Content="新增账号" Style="{StaticResource PrimaryButton}" Visibility="Collapsed" />
            <Button x:Name="BtnRename" Content="保存名称" Style="{StaticResource PrimaryButton}" Visibility="Collapsed" />
          </StackPanel>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
"@
$document = [xml]$xaml
$window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $document))
$window.Icon = New-Object Windows.Media.Imaging.BitmapImage ([uri](Join-Path $PSScriptRoot 'launcher.ico'))
$buttonNames=@('BtnGuardCheck','BtnFlClash','BtnIpCheck','BtnDnsBrowserLeaks','BtnChromeLanguages','BtnChromeFonts','BtnChromeIpPure','BtnEnvironmentRead','BtnWindowsLanguage','BtnWindowsTime','BtnCheck','BtnRecheck','BtnShowAdd','DialogCancel','BtnStart','BtnDeep','BtnBaseline','BtnSwitch','BtnAdd','BtnRename','BtnRefresh','BtnRestore','BtnFolder','AccountList','AccountName','BtnNetwork','BtnFingerprint','BtnFingerprintSave','BtnReports','BtnExport','ReportList')
$script:nextGuardAlert=[DateTime]::MinValue
$script:guardAlert=$null
$script:busy=$false
$script:dialogMode=''
$script:operation=$null
$script:completion=$null
$script:insightResults=@{}
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(150)
$guardTimer=New-Object Windows.Threading.DispatcherTimer
$guardTimer.Interval=[TimeSpan]::FromSeconds(2)
$guardTimer.Add_Tick({
    Update-GuardDisplay
    if ([Launcher]::ConsumeShowRequest()) {Show-GuardWindow}
    if ((Get-GuardSummary $StateRoot) -like '全时段守护未运行*' -and -not $script:operation) {
        Start-Action 'guard-start' '' {param($r) Show-Accounts $r}
    }
})
function Show-GuardState($State,[string]$Summary) {
    $title='尚未完成核验'; $color='#FFD89A'; $background='#26F1D5B4'
    $checking=$State -and $State.Phase -eq '重新检查'
    $unavailable=$Summary -match '未运行|不可读|过期'
    if ($unavailable) {$title='监测暂不可用'}
    elseif ($State -and $State.Phase -eq '警报') {$title='网络提醒 · Claude 继续运行'; $color='#FFB4A6'; $background='#24FF8A73'}
    elseif ($checking) {$title='重新核验中'}
    elseif ($State -and $State.Phase -eq '检测受限') {$title='检测受限 · 请核对网络'}
    elseif ($Summary -like '全时段守护 · 守护中*') {$title='监测正常'; $color='#9BE0B4'; $background='#227BE0A6'}
    $window.FindName('GuardTitle').Text=$title
    $window.FindName('GuardTitle').Foreground=$color
    $window.FindName('GuardStatusPanel').Background=$background
    $window.FindName('GuardSummary').Text=if (-not $unavailable -and $State -and $State.Reason) {$State.Reason} else {$Summary}
    $stamp=[DateTime]::MinValue
    $window.FindName('GuardStamp').Text=if ($State -and [DateTime]::TryParse([string]$State.CheckedAt,[ref]$stamp)) {'最近完整核验：'+$stamp.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')} else {'本次完整核验尚未完成'}
    $button=$window.FindName('BtnGuardCheck')
    $button.Content=if ($checking) {'正在重新核验…'} else {'立即重新检查'}
    $button.IsEnabled=-not $script:busy -and -not $checking -and $State -and $State.Revision -and $Summary -notmatch '未运行|不可读'
    $window.FindName('BtnHomeGuard').Content=$title+' · 查看实时监测 ›'
    if ($script:tray) {$script:tray.Text='Claude 助手 · '+$title}
}
function Show-GuardAlert([string]$Reason) {
    if (-not $script:guardAlert) {
        $alertXml=[xml]@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude 网络提醒" Width="430" SizeToContent="Height" ResizeMode="NoResize"
        ShowActivated="False" ShowInTaskbar="False" Topmost="True" Background="#35271F" Foreground="#FFF4E5">
  <StackPanel Margin="22">
    <TextBlock Text="网络状态提醒" FontSize="21" FontWeight="Bold" Foreground="#F1C296"/>
    <TextBlock x:Name="AlertReason" FontSize="14" TextWrapping="Wrap" Margin="0,12,0,0"/>
    <TextBlock Text="Claude / Claude Code 继续运行。尚未恢复时，每 1 分钟再次提醒；关闭此窗不会停止监测。" FontSize="12" TextWrapping="Wrap" Foreground="#D8C7B6" Margin="0,12,0,18"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="AlertDetails" Content="查看详情" Padding="12,8" Margin="0,0,8,0"/>
      <Button x:Name="AlertLater" Content="稍后提醒（1 分钟）" Padding="12,8"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
        $script:guardAlert=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $alertXml))
        $script:guardAlert.Icon=$window.Icon
        $script:guardAlert.FindName('AlertLater').Add_Click({$script:guardAlert.Close()})
        $script:guardAlert.FindName('AlertDetails').Add_Click({$script:guardAlert.Close();Show-GuardPanel})
        $script:guardAlert.Add_Closed({$script:guardAlert=$null;$script:nextGuardAlert=[DateTime]::UtcNow.AddMinutes(1)})
        $script:guardAlert.Add_ContentRendered({
            $area=[Windows.SystemParameters]::WorkArea
            $script:guardAlert.Left=$area.Right-$script:guardAlert.ActualWidth-16
            $script:guardAlert.Top=$area.Bottom-$script:guardAlert.ActualHeight-16
        })
    }
    $script:guardAlert.FindName('AlertReason').Text=$Reason
    if (-not $script:guardAlert.IsVisible) {$script:guardAlert.Show()}
    [Media.SystemSounds]::Exclamation.Play()
}
function Update-GuardDisplay {
    $summary=Get-GuardSummary $StateRoot
    try {$state=Read-GuardState $StateRoot}
    catch {$state=$null; $summary='全时段守护状态不可读，当前检测暂不可用。'}
    Show-GuardState $state $summary
    $notice=if ($summary -match '未运行|不可读|过期') {$summary} elseif ($state -and $state.AlertKind) {$state.Reason} else {''}
    if ($notice) {
        if ($script:guardAlert) {$script:guardAlert.FindName('AlertReason').Text=$notice}
        if ([DateTime]::UtcNow -ge $script:nextGuardAlert) {
            $script:nextGuardAlert=[DateTime]::UtcNow.AddMinutes(1)
            Show-GuardAlert $notice
        }
    } else {
        if ($script:guardAlert) {$script:guardAlert.Close()}
        $script:nextGuardAlert=[DateTime]::MinValue
    }
}
function Show-GuardPanel {
    Show-GuardWindow
    Show-Page 2
    $window.FindName('GuardPanel').Visibility='Visible'
    $window.FindName('BtnGuardMonitor').Style=$window.Resources['SecondaryButton']
    $window.FindName('PageNetwork').ScrollToTop()
    Update-GuardDisplay
}
function Show-GuardWindow {
    $window.ShowInTaskbar=$true
    $window.WindowState='Normal'
    [void]$window.Activate()
}
function Initialize-GuardTray {
    $script:tray=New-Object Windows.Forms.NotifyIcon
    $script:tray.Icon=New-Object Drawing.Icon (Join-Path $PSScriptRoot 'launcher.ico')
    $script:tray.Text='Claude 全时段守护'
    $menu=New-Object Windows.Forms.ContextMenuStrip
    $show=$menu.Items.Add('打开 Claude 助手')
    $show.Add_Click({Show-GuardWindow})
    $monitor=$menu.Items.Add('实时监测')
    $monitor.Add_Click({Show-GuardPanel})
    $recheck=$menu.Items.Add('立即重新检查')
    $recheck.Add_Click({Show-GuardPanel; Invoke-GuardCheck})
    $quit=$menu.Items.Add('退出界面（停止弹窗）')
    $quit.Add_Click({if (-not $script:operation) {$script:exitInterface=$true; $window.Close()}})
    $script:tray.ContextMenuStrip=$menu
    $script:tray.Add_DoubleClick({Show-GuardWindow})
    $script:tray.Visible=$true
    Set-GuardAutostart
}
function Invoke-GuardCheck {
    if (-not $window.FindName('BtnGuardCheck').IsEnabled) {return}
    Start-Action 'guard-check' '' {param($r)
        Update-GuardDisplay
        Start-Action 'check' '' {param($check) Show-Check $check}
        $window.FindName('StatusText').Text='监测核验完成，正在刷新检查结果…'
    }
}
$window.FindName('BtnGuardCheck').Add_Click({Invoke-GuardCheck})
$window.FindName('BtnGuardMonitor').Add_Click({Show-GuardPanel})
$window.FindName('BtnHomeGuard').Add_Click({Show-GuardPanel})
$window.FindName('BtnGuardClose').Add_Click({
    $window.FindName('GuardPanel').Visibility='Collapsed'
    $window.FindName('BtnGuardMonitor').Style=$window.Resources['GhostButton']
})

# 1.0 sunset hug: 「拥抱一下」 runs the basic check and plays the 10-second hug at the same time.
# hug-motion.mp4 is encoded full range (BT.709): WPF's video renderer here ignores the range flag and shows
# video as 0-255, so a 16-235 encode looks washed out next to the lossless PNG poses it hands over to.
$hugAssets=Join-Path $PSScriptRoot 'assets\hug'
$hugMotion=$window.FindName('HugMotion')
$hugClock=New-Object Diagnostics.Stopwatch
$hugTimer=New-Object Windows.Threading.DispatcherTimer
$hugTimer.Interval=[TimeSpan]::FromMilliseconds(1000.0/60)
$script:hugPlaying=$false
$script:hugEndedAt=$null
$script:hugMediaReady=$false
$script:hugMediaFailed=$false
$script:hugLastPosition=0.0
$script:hugLastProgress=0.0
function Get-HugBitmap([string]$Name) {
    $path=Join-Path $hugAssets $Name
    if (-not [IO.File]::Exists($path)) {return $null}
    try {
        $bitmap=New-Object Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit();$bitmap.CacheOption='OnLoad';$bitmap.UriSource=New-Object Uri $path;$bitmap.EndInit();$bitmap.Freeze()
        $bitmap
    } catch {$null}
}
function Get-HugRamp([double]$Value) {[Math]::Max(0.0,[Math]::Min(1.0,$Value))}
function Get-HugSmooth([double]$Value) {$v=Get-HugRamp $Value;$v*$v*(3-2*$v)}
function Set-HugUi([double]$Opacity) {
    # As in the preview, the navigation, the card and the caption fade together while she walks in.
    foreach ($name in 'Sidebar','HugCard','HugCaption','GlassLayer') {$window.FindName($name).Opacity=$Opacity}
    # Faded controls take no clicks or keyboard focus.
    foreach ($name in 'Sidebar','HugCard') {$window.FindName($name).IsEnabled=$Opacity -ge 0.99}
}
function Hide-HugIdle {
    $fade=New-Object Windows.Media.Animation.DoubleAnimation -ArgumentList ([double]0),([Windows.Duration][TimeSpan]::FromMilliseconds(250))
    $window.FindName('HugIdle').BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
}
function Stop-HugEffect {
    $hugTimer.Stop()
    $script:hugPlaying=$false
    $script:hugEndedAt=$null
    Set-HugUi 1
    $window.FindName('HugLine').Opacity=0
    Update-GlassSource
}
function Show-HugFinal([string]$Reason='') {
    # No motion (animation effects off, missing file or codec): show the last pose at once and keep the card usable.
    if ($script:hugPlaying) {$hugMotion.Pause()}
    Stop-HugEffect
    if ($window.FindName('HugFinal').Source) {
        $window.FindName('HugIdle').BeginAnimation([Windows.UIElement]::OpacityProperty,$null)
        $window.FindName('HugIdle').Opacity=0
        $window.FindName('HugFinal').Opacity=1
        Update-GlassSource
    }
    if ($Reason) {$window.FindName('Hint').Text=$Reason}
}
function Start-HugEffect {
    Show-Details $false
    $idle=$window.FindName('HugIdle')
    $idle.BeginAnimation([Windows.UIElement]::OpacityProperty,$null)
    $idle.Opacity=1
    $window.FindName('HugFinal').Opacity=0
    $window.FindName('HugLine').Opacity=0
    Update-GlassSource
    if (-not [Windows.SystemParameters]::ClientAreaAnimation) {Show-HugFinal;return}
    if ($script:hugMediaFailed -or -not $hugMotion.Source) {Show-HugFinal '拥抱动画无法在本机播放，已直接显示最后一帧；环境检查照常进行。';return}
    $script:hugPlaying=$true
    $script:hugEndedAt=$null
    $script:hugLastPosition=0.0
    $script:hugLastProgress=0.0
    $hugMotion.Position=[TimeSpan]::Zero
    $hugMotion.Play()
    $hugClock.Restart()
    if ($script:hugMediaReady) {Hide-HugIdle}
    Set-HugUi 1
    $hugTimer.Start()
}
function Update-HugFrame {
    if (-not $script:hugPlaying) {$hugTimer.Stop();return}
    if (-not $script:hugMediaReady) {
        if ($hugClock.Elapsed.TotalSeconds -gt 3) {Show-HugFinal '拥抱动画没有按时载入，已直接显示最后一帧；环境检查照常进行。'}
        return
    }
    # As in the reference FilmSplash, a stalled decoder must give the controls back.
    if ($null -eq $script:hugEndedAt) {
        if ($hugMotion.Position.TotalSeconds -gt $script:hugLastPosition+0.005) {
            $script:hugLastPosition=$hugMotion.Position.TotalSeconds
            $script:hugLastProgress=$hugClock.Elapsed.TotalSeconds
        } elseif ($hugClock.Elapsed.TotalSeconds-$script:hugLastProgress -gt 5) {
            Show-HugFinal '拥抱动画播放停滞，已显示最后一帧；环境检查照常进行。'
            return
        }
    }
    # One timeline: 0-10 s follows the video; then the last pose holds, the line shows, and the UI comes back.
    $t=if ($null -ne $script:hugEndedAt) {10+$hugClock.Elapsed.TotalSeconds-$script:hugEndedAt} else {[Math]::Min(10,$hugMotion.Position.TotalSeconds)}
    $window.FindName('HugLine').Opacity=if ($t -lt 12.2) {Get-HugRamp (($t-9.8)/0.8)} else {1-(Get-HugRamp (($t-12.2)/0.8))}
    if ($null -eq $script:hugEndedAt) {Set-HugUi (1-(Get-HugSmooth (($t-2)/4.8)));return}
    $window.FindName('HugFinal').Opacity=Get-HugRamp (($t-10)/0.4)
    Update-GlassSource
    Set-HugUi (Get-HugRamp (($t-12.2)/0.8))
    if ($t -ge 13) {Stop-HugEffect}
}
function Open-HugMotion {
    # Manual mode opens the file on the first Play; MediaOpened then parks it on frame 0 under the idle pose.
    if ($hugMotion.Source -and -not $script:hugMediaReady -and -not $script:hugMediaFailed -and -not $script:hugPlaying) {$hugMotion.Play()}
}
function Update-HugLayout {
    $stage=$window.FindName('HugStage')
    $width=$stage.ActualWidth;$height=$stage.ActualHeight
    if ($width -le 0 -or $height -le 0) {return}
    # Cover the whole window like the preview; crop more from the bottom than the top so her face stays in view.
    $scale=[Math]::Max($width/1586,$height/992)
    $w=1586*$scale;$h=992*$scale;$left=($width-$w)/2;$top=($height-$h)*0.3
    foreach ($name in 'HugMotion','HugIdle','HugFinal','SceneEmpty') {
        $element=$window.FindName($name)
        $element.Width=$w;$element.Height=$h
        [Windows.Controls.Canvas]::SetLeft($element,$left);[Windows.Controls.Canvas]::SetTop($element,$top)
    }
    # The blurred copy behind the glass panels is slightly larger, so the blur never shows a dark edge.
    $glass=$window.FindName('GlassImage')
    $glass.Width=$w*1.04;$glass.Height=$h*1.04
    [Windows.Controls.Canvas]::SetLeft($glass,$left-$w*0.02);[Windows.Controls.Canvas]::SetTop($glass,$top-$h*0.02)
    $i=0
    foreach ($dot in $window.FindName('HugDust').Children) {
        [Windows.Controls.Canvas]::SetLeft($dot,$width*(0.45+(($i*31)%54)/100))
        [Windows.Controls.Canvas]::SetTop($dot,$height*(0.15+(($i*23)%80)/100))
        $i++
    }
}
function Update-GlassSource {
    # The glass blurs whatever still image is showing; while the video plays the panels are faded out.
    $final=$window.FindName('HugFinal')
    $empty=$window.FindName('SceneEmpty')
    $source=if ($window.FindName('MainTabs').SelectedIndex -ne 0 -and $empty.Source) {$empty.Source} elseif ($final.Opacity -ge 0.5 -and $final.Source) {$final.Source} else {$window.FindName('HugIdle').Source}
    $glass=$window.FindName('GlassImage')
    if (-not [object]::ReferenceEquals($glass.Source,$source)) {$glass.Source=$source}
}
$sceneTimer=New-Object Windows.Threading.DispatcherTimer
$sceneTimer.Interval=[TimeSpan]::FromMilliseconds(360)
$sceneTimer.Add_Tick({$sceneTimer.Stop();Complete-ScenePage})
function Complete-ScenePage {
    # Settle the cross-fade explicitly, so no page ever keeps her half visible behind its panel.
    $overview=$window.FindName('MainTabs').SelectedIndex -eq 0
    $empty=$window.FindName('SceneEmpty')
    $empty.BeginAnimation([Windows.UIElement]::OpacityProperty,$null)
    $empty.Opacity=if ($overview) {0.0} else {1.0}
    foreach ($name in 'HugMotion','HugIdle','HugFinal') {$window.FindName($name).Visibility=if ($overview) {'Visible'} else {'Hidden'}}
}
function Update-ScenePage([int]$Index) {
    # She appears only on the overview, where the hug plays; every other page keeps the empty sunset riverside.
    $empty=$window.FindName('SceneEmpty')
    if (-not $empty.Source) {return}
    if ($Index -eq 0) {foreach ($name in 'HugMotion','HugIdle','HugFinal') {$window.FindName($name).Visibility='Visible'}}
    $sceneTimer.Stop()
    if ([Windows.SystemParameters]::ClientAreaAnimation) {
        $target=if ($Index -eq 0) {0.0} else {1.0}
        $fade=New-Object Windows.Media.Animation.DoubleAnimation -ArgumentList $target,([Windows.Duration][TimeSpan]::FromMilliseconds(320))
        $empty.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
        $sceneTimer.Start()
    } else {Complete-ScenePage}
    Update-GlassSource
}
$script:glassKey=$null
function Update-GlassClip {
    # Frosted glass: the blurred scene shows only where a panel floats over it.
    $layer=$window.FindName('GlassLayer')
    if ($layer.ActualWidth -le 0) {return}
    $panels=@('Sidebar','HugCard','DetailsPanel' | ForEach-Object {$window.FindName($_)})
    $page=$window.FindName('MainTabs').SelectedContent
    if ($page -is [Windows.Controls.Border]) {$panels+=$page}
    $shapes=New-Object System.Collections.Generic.List[object]
    foreach ($panel in $panels) {
        if (-not $panel.IsVisible -or $panel.ActualWidth -le 0) {continue}
        try {$bounds=$panel.TransformToVisual($layer).TransformBounds([Windows.Rect]::new(0,0,$panel.ActualWidth,$panel.ActualHeight))} catch {continue}
        $shapes.Add([pscustomobject]@{Rect=$bounds;Radius=$panel.CornerRadius.TopLeft})
    }
    $key=($shapes | ForEach-Object {'{0:0},{1:0},{2:0},{3:0}' -f $_.Rect.X,$_.Rect.Y,$_.Rect.Width,$_.Rect.Height}) -join ';'
    if ($key -eq $script:glassKey) {return}
    $script:glassKey=$key
    $group=New-Object Windows.Media.GeometryGroup
    foreach ($shape in $shapes) {[void]$group.Children.Add((New-Object Windows.Media.RectangleGeometry -ArgumentList $shape.Rect,$shape.Radius,$shape.Radius))}
    $group.Freeze()
    $layer.Clip=$group
}
function Show-Details([bool]$Open) {
    $window.FindName('DetailsPanel').Visibility=if ($Open) {'Visible'} else {'Collapsed'}
    $window.FindName('BtnDetails').Content=if ($Open) {'收起明细 ‹'} else {'查看检查明细 ›'}
}
function Set-BasicTiles($Items) {
    $items=@($Items)
    $window.FindName('Tiles').ItemsSource=$items
    $window.FindName('TileDots').ItemsSource=$items
    $parts=@(foreach ($label in '需处理','请核对','未验证','已核对') {
        $count=@($items | Where-Object Label -eq $label).Count
        if ($count) {$label+' '+$count}
    })
    $window.FindName('CardSummary').Text=if (-not $items.Count) {'暂无基础检查项目'} elseif (@($items | Where-Object {$_.Detail -ne '尚未检查'}).Count -eq 0) {$items.Count.ToString()+' 项尚未检查'} elseif ($parts.Count -eq 1 -and $parts[0] -like '已核对*') {$items.Count.ToString()+' 项均已核对'} else {$parts -join ' · '}
}
function Initialize-HugDust {
    if (-not [Windows.SystemParameters]::ClientAreaAnimation) {return}
    $canvas=$window.FindName('HugDust')
    for ($i=0;$i -lt 16;$i++) {
        $brush=New-Object Windows.Media.RadialGradientBrush
        $brush.GradientStops.Add((New-Object Windows.Media.GradientStop -ArgumentList ([Windows.Media.Color]::FromArgb(255,255,245,213)),0.0))
        $brush.GradientStops.Add((New-Object Windows.Media.GradientStop -ArgumentList ([Windows.Media.Color]::FromArgb(200,255,241,186)),0.35))
        $brush.GradientStops.Add((New-Object Windows.Media.GradientStop -ArgumentList ([Windows.Media.Color]::FromArgb(0,255,241,186)),1.0))
        $brush.Freeze()
        $size=if ($i%4 -eq 0) {10} else {7}
        $dot=New-Object Windows.Shapes.Ellipse
        $dot.Width=$size;$dot.Height=$size;$dot.Fill=$brush;$dot.Opacity=0
        $move=New-Object Windows.Media.TranslateTransform
        $dot.RenderTransform=$move
        [void]$canvas.Children.Add($dot)
        # Same drift as the preview: rise about 134 px and drift 32 px left over 7-11 s, glowing in and out.
        $seconds=7+$i%5
        $life=[Windows.Duration][TimeSpan]::FromSeconds($seconds)
        $x=New-Object Windows.Media.Animation.DoubleAnimation -ArgumentList ([double]0),([double]-32),$life
        $y=New-Object Windows.Media.Animation.DoubleAnimation -ArgumentList ([double]24),([double]-110),$life
        $glow=New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $glow.Duration=$life
        foreach ($key in @(@(0.0,0.0),@(0.2,0.65),@(0.8,0.35),@(1.0,0.0))) {
            [void]$glow.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame -ArgumentList ([double]$key[1]),([Windows.Media.Animation.KeyTime]::FromPercent([double]$key[0]))))
        }
        foreach ($animation in @($x,$y,$glow)) {
            $animation.BeginTime=[TimeSpan]::FromSeconds(($i*1.7)%$seconds)
            $animation.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
        }
        $move.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$x)
        $move.BeginAnimation([Windows.Media.TranslateTransform]::YProperty,$y)
        $dot.BeginAnimation([Windows.UIElement]::OpacityProperty,$glow)
    }
}
$hugMotion.Add_MediaOpened({
    $script:hugMediaReady=$true
    if ($script:hugPlaying) {Hide-HugIdle} else {$hugMotion.Pause();$hugMotion.Position=[TimeSpan]::Zero}
})
$hugMotion.Add_MediaEnded({
    if (-not $script:hugPlaying) {return}
    $hugMotion.Pause()
    $script:hugEndedAt=$hugClock.Elapsed.TotalSeconds
})
$hugMotion.Add_MediaFailed({
    $script:hugMediaFailed=$true
    if ($script:hugPlaying) {Show-HugFinal '拥抱动画无法在本机播放，已直接显示最后一帧；环境检查照常进行。'}
})
$hugTimer.Add_Tick({Update-HugFrame})

function Update-LaunchButton {
    $window.FindName('BtnStart').IsEnabled=-not $script:busy
    $window.FindName('BtnStart').ToolTip='打开 Claude；网络异常只提醒，不锁定启动。'
    $window.FindName('HeroHint').Text='网络异常只提醒 · 拥抱与启动可分别使用'
}
function Update-AccountSelection {
    $selected=$window.FindName('AccountList').SelectedItem
    $window.FindName('SelName').Text=if ($selected) {$selected.Name} else {'未选择'}
    $canSwitch=$selected -and $selected.Id -ne $script:currentAccount
    $window.FindName('BtnSwitch').IsEnabled=$canSwitch -and -not $script:busy
    $window.FindName('SwitchLabel').Text=if ($canSwitch) {'切换到选中账号'} else {'当前正在使用'}
}
function Set-Busy([bool]$Busy) {
    $script:busy=$Busy
    foreach ($name in $buttonNames) { $window.FindName($name).IsEnabled = -not $Busy }
    $window.FindName('BusyBar').Visibility = if ($Busy) {'Visible'} else {'Collapsed'}
    Update-LaunchButton
    Update-AccountSelection
    Update-EnvironmentButtons
    Update-GuardDisplay
}
function Start-Action($Action, $Target, [scriptblock]$Finished, [string]$Name = '') {
    if ($script:operation) { return }
    $core=Join-Path $PSScriptRoot 'claude-switch.ps1'
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $info.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$core+'" -Command '+$Action+' -StateRoot "'+$StateRoot+'"'
    if ($Target) {
        if ($Target -cnotmatch '^(primary|A|B|p-[a-f0-9]{32})$') { throw '账号标识无效，请刷新列表。' }
        $info.Arguments+=' -Account '+$Target
    }
    if ($Name) { $info.Arguments+=' -NameEncoded '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Name)) }
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding=New-Object Text.UTF8Encoding($false)
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$info
    $watch=[Diagnostics.Stopwatch]::StartNew()
    [void]$process.Start()
    $script:operation=[pscustomobject]@{ Action=$Action; Process=$process; Watch=$watch; TimedOut=$false; Output=$process.StandardOutput.ReadToEndAsync(); Error=$process.StandardError.ReadToEndAsync() }
    $script:completion=$Finished
    Set-Busy $true
    $window.FindName('StatusText').Text='正在处理，请稍候…'
    $window.FindName('Hint').Text=if ($Action -in @('switch','restore')) {'正在备份和校验。数据量较大时需要几分钟，请保持窗口打开。'} elseif ($Action -eq 'check') {'HTTPS 阶段最多 60 秒，通过立即结束；另计本机准备时间。超时只标记未验证，不结束已运行的 Claude。'} elseif ($Action -eq 'flclash-check') {'正在本地读取 FlClash 版本、脚本绑定、覆写键与生成配置，不修改网络。'} elseif ($Action -eq 'deep-check') {'正在独立检测 HTTPS、IPv6、UDP 和 WebRTC，通常需要 20–60 秒。检测不修改现有连接。'} elseif ($Action -eq 'network-insights') {'正在核对 Claude 相关域名的多个出口与 DNS；目标较多时需要更长时间。每个请求有超时限制，不自动重试、不切换节点。'} elseif ($Action -like 'fingerprint-*') {'正在本地临时 Edge 中采集设备特征，不连接检测网站、不上传特征。'} elseif ($Action -in @('environment-read','timezone-set','format-set','language-first')) {'正在处理 Windows 环境设置；不操作网络或 Claude 进程。'} elseif ($Action -in @('status','account-add','account-rename')) {'正在处理本地账号列表，不读取登录数据，不连接外网。'} else {'正在核验 Claude 相关域名的代理与系统 / TUN 出口；每个请求有超时限制。'}
    $timer.Start()
}
$timer.Add_Tick({
    if (-not $script:operation) { return }
    # HTTPS gets its own minute; allow time for local checks and worker completion.
    if ($script:operation.Action -eq 'check' -and $script:operation.Watch.ElapsedMilliseconds -ge 75000 -and -not $script:operation.Process.HasExited) {
        $script:operation.TimedOut=$true
        try { $script:operation.Process.Kill() }
        catch [InvalidOperationException] { if (-not $script:operation.Process.HasExited) { throw } }
    }
    if (-not $script:operation.Process.HasExited -and -not $script:operation.TimedOut) {
        $elapsed=[int][Math]::Floor($script:operation.Watch.Elapsed.TotalSeconds)
        $window.FindName('StatusText').Text='检测 / 操作进行中 · '+$elapsed+' 秒'
        return
    }
    $timer.Stop()
    $op=$script:operation; $callback=$script:completion
    $script:operation=$null; $script:completion=$null
    try {
        if ($op.TimedOut) {
            $checks=@('Claude 桌面版','代理内核','TUN 网卡','本地代理端口','代理 HTTPS 出口' | ForEach-Object {
                [pscustomobject]@{Name=$_;State='unknown';Detail='基础检查超时（含准备阶段共 75 秒），未取得完整结果。';Blocking=$true}
            })
            Show-Check ([pscustomobject]@{Ready=$false;Checks=$checks;CheckedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')})
            $window.FindName('StatusText').Text='基础检查已停止（含准备阶段共 75 秒）'
            $window.FindName('Hint').Text='未取得完整结果，可稍后重新检测。Claude 仍可启动和继续使用。'
            return
        }
        $output=$op.Output.GetAwaiter().GetResult()
        $errorOutput=$op.Error.GetAwaiter().GetResult()
        if ([string]::IsNullOrWhiteSpace($output)) { throw ('后台操作未返回结果。' + $errorOutput) }
        $result=$output | ConvertFrom-Json
        if ($op.Process.ExitCode -ne 0 -or $result.Error) { throw $result.Error }
        & $callback $result
        if ($result.ReportPath) { Refresh-Reports }
        if ($result.ReportError) { $window.FindName('Hint').Text=$result.ReportError }
    } catch {
        $window.FindName('StatusText').Text='操作未完成'
        $window.FindName('Hint').Text=$_.Exception.Message
        if ($script:dialogMode) {
            $window.FindName('DialogError').Text=$_.Exception.Message
            $window.FindName('DialogError').Visibility='Visible'
        }
    } finally { $op.Process.Dispose(); Set-Busy ($null -ne $script:operation) }
})
function ConvertTo-CheckItems($Checks) {
    @($Checks | ForEach-Object {
        $label=switch ($_.State) {'ok' {'已核对'} 'fail' {'需处理'} 'warn' {'请核对'} 'unknown' {'未验证'} default {'信息'}}
        $color=switch ($_.State) {'ok' {'#9BE0B4'} 'fail' {'#FFB4A6'} 'warn' {'#FFD89A'} 'unknown' {'#D8C7B6'} default {'#CDBBA9'}}
        $badge=switch ($_.State) {'ok' {'#2E7BE0A6'} 'fail' {'#38FF8A73'} 'warn' {'#33FFC46B'} 'unknown' {'#26F1D5B4'} default {'#1FF1D5B4'}}
        [pscustomobject]@{ Name=$_.Name; Detail=$_.Detail; Label=$label; Color=$color; Badge=$badge; Source=$_.Source; Evidence=$_.Evidence; Advice=$_.Advice; EvidenceVisibility=$(if ($_.Source -or $_.Evidence -or $_.Advice) {'Visible'} else {'Collapsed'}) }
    })
}
function ConvertTo-CheckGroups($Checks) {
    @($Checks | Group-Object {if ($_.Group) {$_.Group} else {'结果与范围'}} | ForEach-Object {
        $items=@(ConvertTo-CheckItems $_.Group)
        $state='info'
        foreach ($candidate in @('fail','warn','unknown','ok')) {
            if (@($_.Group | Where-Object State -eq $candidate).Count) {$state=$candidate;break}
        }
        $badge=@(ConvertTo-CheckItems @([pscustomobject]@{State=$state}))[0]
        $attention=@($_.Group | Where-Object {$_.State -in @('fail','warn','unknown')}).Count
        [pscustomobject]@{Name=$_.Name;Items=$items;CountLabel=($items.Count.ToString()+' 项');Label=$badge.Label;Color=$badge.Color;Badge=$badge.Badge;Summary=$(if ($attention) {"$attention 项待核对 / 未验证 · 展开查看"} else {'展开查看测量结果、来源和细节'})}
    })
}
function Update-InsightView([string]$Prefix) {
    $result=$script:insightResults[$Prefix]
    if (-not $result) { return }
    $query=$window.FindName($Prefix+'Search').Text.Trim()
    $attentionOnly=$window.FindName($Prefix+'Attention').IsChecked
    $checks=@($result.Checks | Where-Object {
        $matchesText=-not $query -or (($_.Name,$_.Detail,$_.Group,$_.Source,$_.Evidence) -join ' ').IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0
        $matchesText -and (-not $attentionOnly -or $_.State -in @('fail','warn','unknown'))
    })
    $window.FindName($Prefix+'Groups').ItemsSource=@(ConvertTo-CheckGroups $checks)
    $window.FindName($Prefix+'Empty').Visibility=if ($checks.Count) {'Collapsed'} else {'Visible'}
    $window.FindName($Prefix+'EmptyText').Text=if (@($result.Checks).Count) {'没有匹配的结果。清空搜索或取消筛选，查看全部项目。'} else {'这次检测没有返回项目，请查看下方提示后重试。'}
    $information=@($result.Checks | Where-Object State -eq 'info').Count
    $window.FindName($Prefix+'Summary').Text='显示 '+$checks.Count+' / '+@($result.Checks).Count+" 项 · 含 $information 项说明 · 保存于本机，时间为实际采集时间。"
}
function Show-Insights($Result) {
    $fingerprint=$Result.Kind -eq 'Fingerprint'
    $title=if ($fingerprint) {'设备特征'} else {'网络诊断'}
    $prefix=if ($fingerprint) {'Fingerprint'} else {'Insight'}
    $script:insightResults[$prefix]=$Result
    $metrics=@(
        [pscustomobject]@{Label='本次结果';Count=@($Result.Checks).Count;Color='#F1C296'}
        [pscustomobject]@{Label='已核对';Count=@($Result.Checks | Where-Object State -eq 'ok').Count;Color='#9BE0B4'}
        [pscustomobject]@{Label='待核对';Count=@($Result.Checks | Where-Object {$_.State -in @('fail','warn')}).Count;Color='#FFD89A'}
        [pscustomobject]@{Label='未验证';Count=@($Result.Checks | Where-Object State -eq 'unknown').Count;Color='#D8C7B6'}
    )
    $window.FindName($prefix+'Metrics').ItemsSource=$metrics
    $window.FindName($prefix+'Title').Text=$title+' · 最近采集 '+$Result.CheckedAt
    if ($fingerprint) {
        $verdict=@($Result.Checks | Where-Object {$_.Name -in @('设备基准对比','设备基准')} | Select-Object -First 1)
        $window.FindName('FingerprintVerdict').Text=if ($verdict.Count) {$verdict[0].Detail} else {'本次设备特征结果'}
        $window.FindName('FingerprintTitle').Text='设备特征 · 本次采样结果'
        $window.FindName('FingerprintTime').Text='采集时间：'+$Result.CheckedAt+' · 本地独立 Edge'
        $changes=@($Result.Checks | Where-Object {$_.State -eq 'warn' -and $_.Name -ne '设备基准对比'})
        $window.FindName('FpDiffCard').Visibility=if ($changes.Count) {'Visible'} else {'Collapsed'}
        $window.FindName('FpDiffCount').Text=$changes.Count.ToString()+' 项变化'
        $window.FindName('FpDiff').ItemsSource=@(ConvertTo-CheckItems $changes)
        $spotlight=@(ConvertTo-CheckItems @($Result.Checks | Where-Object Name -in @('可见字体样本','Emoji 渲染摘要','Emoji 像素特征')))
        foreach ($item in $spotlight) {if ($item.Name -eq '可见字体样本') {$item.Detail=($item.Evidence -split "`n")[0]}}
        $window.FindName('FingerprintSpotlight').ItemsSource=$spotlight
        $regional=@(ConvertTo-CheckItems @($Result.Checks | Where-Object Group -eq '时区与语言（忽略影响）'))
        foreach ($item in $regional) {$item.Label='忽略影响'}
        $window.FindName('RegionalChecks').ItemsSource=$regional
        $window.FindName('RegionalNote').Text=if ($regional.Count) {'只读观察；不计入 20 项指纹基准，不影响启动。设置修改需在环境设置中单独应用。'} else {'此历史记录没有区域信息，重新采集后显示；不影响启动。'}
    } else {Show-NetworkAddresses $Result}
    Update-InsightView $prefix
    $window.FindName('StatusText').Text=$title+'结果已载入'
    $window.FindName('Hint').Text=$Result.Message
}

function Show-FlClashCheck($Result,[bool]$Historical=$false) {
    $window.FindName('FlClashChecks').ItemsSource=@(ConvertTo-CheckItems $Result.Checks)
    $attention=@($Result.Checks | Where-Object State -in @('fail','warn','unknown')).Count
    $window.FindName('FlClashSummary').Text=$(if ($Historical) {'历史记录 · '} else {'本次检查 · '})+$Result.CheckedAt+' · '+$attention+' 项待处理 / 核对；浏览器泄露测试尚需单独运行。'
}

function Show-NetworkAddresses($Result) {
    $live=$null -ne $Result.PSObject.Properties['LiveDetails']
    $observed=if ($live) {@($Result.LiveDetails)} else {@($Result.Observations)}
    $window.FindName('AddressStamp').Text=$Result.CheckedAt+$(if ($live) {' · 本次采集，完整 IP 仅显示在当前窗口'} else {' · 历史记录，IP 仅保留摘要；重新检测可查看完整地址'})
    $cards=@(foreach ($hostName in @($observed | Where-Object {Test-ClaudeDomain $_.Provider} | ForEach-Object Provider | Sort-Object -Unique)) {
        foreach ($route in @('Proxy','System')) {
            $routeName=if ($route -eq 'Proxy') {'显式代理'} else {'系统 / TUN'}
            $name=$hostName+' · '+$routeName
            $row=@($Result.Checks | Where-Object Name -eq $name | Select-Object -First 1)
            $data=@($observed | Where-Object {$_.Type -eq 'Egress' -and $_.Provider -eq $hostName -and $_.Route -eq $route} | Select-Object -First 1)
            $state=if ($row.Count) {$row[0].State} else {'unknown'}
            $badge=@(ConvertTo-CheckItems @([pscustomobject]@{State=$state}))[0]
            $address='未取得地址';$detail=if ($row.Count) {$row[0].Detail} else {'尚无此路径的有效测量。'}
            if ($data.Count) {
                $item=$data[0]
                $address=if ($live) {$item.Address} else {'摘要 '+$item.Hash.Substring(0,12)}
                $detail=$item.Country+' · '+$item.Family+' · '+$item.Milliseconds+' ms（请求耗时）'
            }
            [pscustomobject]@{Title=$name;Address=$address;Detail=$detail;Label=$badge.Label;Color=$badge.Color}
        }
    })
    $window.FindName('ClaudeEndpoints').ItemsSource=$cards
    $dns=@($observed | Where-Object Type -eq 'DNS')
    $window.FindName('DnsHeadline').Text=if ($dns.Count) {
        $unique=@($dns | Select-Object -ExpandProperty Hash -Unique).Count
        $china=@($dns | Where-Object Country -eq 'CN' | Select-Object -ExpandProperty Hash -Unique).Count
        $ecs=@($dns | Where-Object Ecs).Count
        "合并 $unique 个解析器 · 中国 $china 个 · 含 ECS 的观测 $ecs 条。意外结果需核对，数量和位置不单独判定泄露。"
    } else {'本次未取得解析器信息；请查看 DNS 解析路径中的具体原因。'}
    $window.FindName('DnsResolvers').ItemsSource=@($dns | ForEach-Object {
        $routeName=if ($_.Route -eq 'Proxy') {'显式代理'} else {'系统 / TUN'}
        $location=(@($_.Country,$_.Geo,$_.Organization) | Where-Object {$_}) -join ' · '
        if (-not $location) {$location='服务未提供归属信息'}
        [pscustomobject]@{Title=$_.Provider+' · '+$routeName+' · '+$_.Family;Address=$(if ($live) {$_.Address} else {'摘要 '+$_.Hash.Substring(0,12)});Detail=$location;Label=$(if ($_.Ecs) {'含 ECS'} elseif ($_.Country -eq 'CN') {'中国 · 请核对'} else {'已观察'});Color=$(if ($_.Ecs -or $_.Country -eq 'CN') {'#FFD89A'} else {'#F1C296'})}
    })
}


function Set-DeepResults($Checks,[string]$Stamp) {
    $window.FindName('DeepChecks').ItemsSource=@(ConvertTo-CheckItems $Checks)
    $window.FindName('DeepStamp').Text=$Stamp
    $rtc=@($Checks | Where-Object Name -eq '浏览器 WebRTC' | Select-Object -First 1)
    if ($rtc.Count) {
        $item=@(ConvertTo-CheckItems $rtc)[0]
        $window.FindName('WebRtcSummary').Text=$item.Label+' · '+$item.Detail
        $window.FindName('WebRtcSummary').Foreground=$item.Color
    } else {
        $window.FindName('WebRtcSummary').Text='未验证 · 本次未完成浏览器 WebRTC 采集，请查看下方原因。'
        $window.FindName('WebRtcSummary').Foreground='#D8C7B6'
    }
}
function Show-Check($Result) {
    if ($Result.Deep) {
        Set-DeepResults $Result.Checks $Result.CheckedAt
        $failed=@($Result.Checks | Where-Object State -in @('fail','warn')).Count
        $unknown=@($Result.Checks | Where-Object State -eq 'unknown').Count
        $window.FindName('StatusText').Text="深度检测完成：$failed 项出口差异，$unknown 项未验证。"
        $window.FindName('Hint').Text=$Result.Message
    } else {
        $window.FindName('Checks').ItemsSource=@(ConvertTo-CheckItems $Result.Checks)
        Set-BasicTiles @(ConvertTo-CheckItems @($Result.Checks | Where-Object Name -in @('Claude 桌面版','代理内核','TUN 网卡','本地代理端口','代理 HTTPS 出口','全时段守护')))
        $window.FindName('BasicStamp').Text=$Result.CheckedAt
        Update-LaunchButton
        $window.FindName('VerdictPanel').Visibility='Visible'
        $attention=@($Result.Checks | Where-Object {$_.Blocking -or $_.State -in @('fail','unknown')}).Count
        $window.FindName('VerdictText').Text=if ($attention) {'检测完成 · 请留意提醒'} else {'检测通过'}
        $window.FindName('VerdictText').Foreground=if ($attention) {'#FFD89A'} else {'#9BE0B4'}
        $window.FindName('StatusText').Text=if ($attention) {'检测发现异常或未验证项；仅作提醒，Claude 仍可使用。'} else {'基础检查通过，可以启动 Claude。'}
        $window.FindName('Hint').Text='后台持续监测网络。异常期间每分钟提示，不结束、不重启 Claude / Claude Code。'
        $baseline=@($Result.Checks | Where-Object Name -eq '星链出口策略')
        if ($baseline.Count) {$window.FindName('BaselineText').Text=$baseline[0].Detail}
    }
}
function Refresh-Reports {
    $script:reports=@(Get-DiagnosticReports $StateRoot)
    $labels=@{FlClash='FlClash / DNS';Basic='基础';Deep='深度';Network='网络';Fingerprint='特征';Error='无法读取'}
    $entries=@($script:reports | ForEach-Object { [pscustomobject]@{Label=$_.CheckedAt+' · '+$labels[$_.Kind];Entry=$_} })
    $window.FindName('ReportList').ItemsSource=$entries
    if ($entries.Count) { $window.FindName('ReportList').SelectedIndex=0 }
}
function Load-LatestReports {
    Refresh-Reports
    foreach ($kind in @('Basic','Deep','Network','Fingerprint','FlClash')) {
        $latest=@($script:reports | Where-Object Kind -eq $kind | Select-Object -First 1)
        if (-not $latest.Count) { continue }
        $report=$latest[0].Report
        if ($kind -eq 'FlClash') {Show-FlClashCheck $report $true}
        elseif ($kind -in @('Network','Fingerprint')) { Show-Insights $report }
        else {
            $control=if ($kind -eq 'Basic') {'Checks'} else {'DeepChecks'}
            $stamp=if ($kind -eq 'Basic') {'BasicStamp'} else {'DeepStamp'}
            $window.FindName($control).ItemsSource=@(ConvertTo-CheckItems $report.Checks)
            $window.FindName($stamp).Text='历史记录 · '+$report.CheckedAt+'（可重新检查）'
            if ($kind -eq 'Deep') {Set-DeepResults $report.Checks ('历史记录 · '+$report.CheckedAt)}
        }
    }
}
function Show-Message($Result) {
    $window.FindName('StatusText').Text='操作完成'
    $window.FindName('Hint').Text=$Result.Message
    if ($Result.Status) { Show-Accounts $Result.Status $Result.Selected }
}
function Show-Accounts($Result, [string]$Selected = '') {
    $script:currentAccount=$Result.Current
    foreach ($name in @('AccountText','CurName')) {$window.FindName($name).Text=$Result.CurrentName}
    $window.FindName('HeroAvatarText').Text=$Result.CurrentName.Substring(0,1)
    $list=$window.FindName('AccountList'); $list.ItemsSource=@($Result.Profiles)
    if (-not $Selected) { $Selected=$Result.Current }
    $list.SelectedItem=@($Result.Profiles | Where-Object Id -eq $Selected)[0]
    Update-AccountSelection
}

function Update-EnvironmentButtons {
    foreach ($kind in @('Timezone','Format','Language')) {
        $choice=$window.FindName($kind+'Choice')
        $choice.IsEnabled=$null -ne $script:environmentSettings -and -not $script:busy
        $window.FindName('Btn'+$kind+'Apply').IsEnabled=$choice.IsEnabled -and $choice.SelectedValue -and $choice.SelectedValue -ne $script:environmentSettings.$kind
    }
}
function Show-EnvironmentPreferences($Result) {
    $script:environmentSettings=$Result
    foreach ($kind in @('Timezone','Format','Language')) {
        $items=switch ($kind) {'Timezone' {$Result.Timezones} 'Format' {$Result.Formats} 'Language' {$Result.Languages}}
        $choice=$window.FindName($kind+'Choice');$choice.ItemsSource=@($items);$choice.SelectedValue=$Result.$kind
        $window.FindName($kind+'Current').Text='当前：'+$choice.SelectedItem.Label
    }
    Update-EnvironmentButtons
}
function Apply-EnvironmentChoice([string]$Kind) {
    if ($script:busy -or -not $script:environmentSettings) {return}
    $choice=$window.FindName($Kind+'Choice');$selected=$choice.SelectedItem
    if (-not $selected -or $selected.Id -eq $script:environmentSettings.$Kind) {return}
    $label=switch ($Kind) {'Timezone' {'系统时区'} 'Format' {'Windows 区域格式'} 'Language' {'Windows 首选语言'}}
    $summary=$label+"`n"+$window.FindName($Kind+'Current').Text+"`n改为："+$selected.Label+"`n`n这会修改 Windows 设置，不仅是本工具。会先保存原设置；不重启 Claude、不注销系统。确认应用？"
    if ([Windows.MessageBox]::Show($window,$summary,'确认环境设置','YesNo','Question') -ne 'Yes') {return}
    $action=switch ($Kind) {'Timezone' {'timezone-set'} 'Format' {'format-set'} 'Language' {'language-first'}}
    Start-Action $action '' {param($r)
        Show-EnvironmentPreferences $r.Environment
        $window.FindName('EnvironmentFeedback').Text=$r.Message
        Show-Message $r
    } $selected.Id
}

function Show-Page([int]$Index) {
    $window.FindName('MainTabs').SelectedIndex=$Index
    $nav=@('Overview','Accounts','Network','Fingerprint','Reports','About','Environment')
    $window.FindName('Nav'+$nav[$Index]).IsChecked=$true
    Update-ScenePage $Index
}
function Update-Narrow([double]$Width) {
    $narrow=$Width -lt 900
    # Narrow windows keep only the icons in the floating navigation, as the preview does below 800 px.
    foreach ($name in @('BrandText','NavOverviewText','NavNetworkText','NavFingerprintText','NavAccountsText','NavReportsText','NavAboutText','NavEnvironmentText')) {
        $window.FindName($name).Visibility=if ($narrow) {'Collapsed'} else {'Visible'}
    }
    # Pages float as glass panels on the left and leave her visible on the right when there is room.
    $content=$Width-16
    $panel=[Math]::Min(900,[Math]::Max(600,$content*0.64))
    $right=if ($content-$panel-44 -ge 220) {$content-$panel-22} else {22}
    $window.Resources['PanelMargin']=[Windows.Thickness]::new(22,80,$right,22)
    $window.FindName('DetailsPanel').Width=if ($content -ge 900) {[Math]::Min(500,$content*0.42)} else {[Math]::Max(300,$content-44)}
}
function Open-AccountDialog([string]$Mode, $Profile=$null) {
    if ($script:busy) {return}
    $script:dialogMode=$Mode
    $script:renameId=if ($Profile) {$Profile.Id} else {''}
    $window.FindName('DialogTitle').Text=if ($Mode -eq 'add') {'新增账号'} else {'重命名账号'}
    $window.FindName('AccountName').Text=if ($Profile) {$Profile.Name} else {''}
    $window.FindName('DialogError').Visibility='Collapsed'
    $window.FindName('BtnAdd').Visibility=if ($Mode -eq 'add') {'Visible'} else {'Collapsed'}
    $window.FindName('BtnRename').Visibility=if ($Mode -eq 'rename') {'Visible'} else {'Collapsed'}
    $window.FindName('MainContent').IsEnabled=$false
    $window.FindName('DialogHost').Visibility='Visible'
    [void]$window.FindName('AccountName').Focus()
    $window.FindName('AccountName').SelectAll()
}
function Close-AccountDialog {
    if ($script:busy) {return}
    $script:dialogMode=''
    $window.FindName('DialogHost').Visibility='Collapsed'
    $window.FindName('MainContent').IsEnabled=$true
    [void]$window.FindName('BtnShowAdd').Focus()
}
function Save-AccountDialog {
    if ($script:busy -or -not $script:dialogMode) {return}
    $name=$window.FindName('AccountName').Text.Trim()
    if (-not $name) {
        $window.FindName('DialogError').Text='请输入账号名称。'
        $window.FindName('DialogError').Visibility='Visible'
        return
    }
    $action=if ($script:dialogMode -eq 'add') {'account-add'} else {'account-rename'}
    Start-Action $action $script:renameId {param($r)
        Show-Message $r
        $script:dialogMode=''
        $window.FindName('DialogHost').Visibility='Collapsed'
        $window.FindName('MainContent').IsEnabled=$true
        [void]$window.FindName('AccountList').Focus()
    } $name
}
$window.FindName('InsightSearch').Add_TextChanged({Update-InsightView 'Insight'})
$window.FindName('InsightAttention').Add_Checked({Update-InsightView 'Insight'})
$window.FindName('InsightAttention').Add_Unchecked({Update-InsightView 'Insight'})
$window.FindName('FingerprintSearch').Add_TextChanged({Update-InsightView 'Fingerprint'})
$window.FindName('FingerprintAttention').Add_Checked({Update-InsightView 'Fingerprint'})
$window.FindName('FingerprintAttention').Add_Unchecked({Update-InsightView 'Fingerprint'})
$window.FindName('ReportList').Add_SelectionChanged({
    $selected=$window.FindName('ReportList').SelectedItem
    if (-not $selected) {return}
    $entry=$selected.Entry
    if ($entry.Error) {
        $window.FindName('ReportComparison').Text=$entry.Error
        $window.FindName('ReportGroups').ItemsSource=@()
        return
    }
    $previous=@($script:reports | Where-Object {$_.Kind -eq $entry.Kind -and $_.Path -ne $entry.Path -and $_.CheckedAt -le $entry.CheckedAt} | Select-Object -First 1)
    $window.FindName('ReportComparison').Text=Compare-DiagnosticReports $entry.Report $(if ($previous.Count) {$previous[0].Report} else {$null})
    $window.FindName('ReportGroups').ItemsSource=@(ConvertTo-CheckGroups $entry.Report.Checks)
})
$window.FindName('BtnReports').Add_Click({Refresh-Reports})
$window.FindName('BtnExport').Add_Click({
    $selected=$window.FindName('ReportList').SelectedItem
    if (-not $selected -or -not $selected.Entry.Report) {$window.FindName('Hint').Text='先选择一份可读取的记录。';return}
    $dialog=New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter='Markdown 报告 (*.md)|*.md|JSON 数据 (*.json)|*.json'
    $dialog.FileName='Claude-诊断-'+$selected.Entry.Kind+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')
    if ($dialog.ShowDialog($window)) {
        try {Export-DiagnosticReport $selected.Entry.Report $dialog.FileName;$window.FindName('Hint').Text='已导出到：'+$dialog.FileName}
        catch {$window.FindName('Hint').Text='导出未完成：'+$_.Exception.Message}
    }
})
$window.FindName('BtnCheck').Add_Click({
    Start-Action 'check' '' {param($r) Show-Check $r}
    # The hug plays only when this click really started a check; it never launches Claude when it ends.
    if ($script:operation -and $script:operation.Action -eq 'check') {Start-HugEffect}
})
$window.FindName('BtnRecheck').Add_Click({ Start-Action 'check' '' {param($r) Show-Check $r} })
$window.FindName('BtnFlClash').Add_Click({ Start-Action 'flclash-check' '' {param($r) Show-FlClashCheck $r; Refresh-Reports; $window.FindName('StatusText').Text='FlClash / DNS 配置检查完成'; $window.FindName('Hint').Text='展开结果查看依据和修复路径；本次未修改 FlClash，未发送 DNS 泄露探测。'} })
$window.FindName('BtnIpCheck').Add_Click({try {[void](Open-DnsTestPage IPCheck -Owner $window -StateRoot $StateRoot)} catch {$window.FindName('Hint').Text=$_.Exception.Message}})
$window.FindName('BtnDnsBrowserLeaks').Add_Click({try {Open-DnsTestPage BrowserLeaks} catch {$window.FindName('Hint').Text=$_.Exception.Message}})
$window.FindName('BtnNetwork').Add_Click({ Start-Action 'network-insights' '' {param($r) Show-Insights $r} })
$window.FindName('BtnFingerprint').Add_Click({ Start-Action 'fingerprint-check' '' {param($r) Show-Insights $r} })
$window.FindName('BtnFingerprintSave').Add_Click({ Start-Action 'fingerprint-save' '' {param($r) Show-Insights $r} })
$window.FindName('BtnDeep').Add_Click({
    $answer=[Windows.MessageBox]::Show($window,'将向 ipify、Google / Cloudflare STUN 发送少量请求，并用独立 Edge 临时配置检测 WebRTC。不会修改网络、关闭 Claude 或读取现有浏览器资料。结果只表示本次路径，可能需要约 1 分钟。开始检测？','只读深度检测','YesNo','Information')
    if ($answer -eq 'Yes') { Start-Action 'deep-check' '' {param($r) Show-Check $r} }
})
$window.FindName('BtnStart').Add_Click({
    if ($script:busy) {return}
    Start-Action 'start' '' {param($r) Show-Message $r}
})
$window.FindName('BtnBaseline').Add_Click({
    $answer=[Windows.MessageBox]::Show($window,'将重新核验全部已发现 Claude 域名路径，并为当前账号记录出口摘要。后续仍按星链 AS14593 核验并提醒，不锁定当前 IP。继续？','记录本次星链核验','YesNo','Question')
    if ($answer -eq 'Yes') { Start-Action 'baseline' '' {param($r) Show-Message $r} }
})
$window.FindName('AccountList').Add_SelectionChanged({Update-AccountSelection})
$window.FindName('BtnSwitch').Add_Click({
    $selected=$window.FindName('AccountList').SelectedItem
    if (-not $selected) { $window.FindName('Hint').Text='请先选择账号。'; return }
    if ($selected.Id -eq $script:currentAccount) { $window.FindName('Hint').Text='当前已经使用此账号，回到概览拥抱一下后即可启动。'; return }
    $answer=[Windows.MessageBox]::Show($window, ('将保存当前桌面登录状态，并切换到「'+$selected.Name+'」。请先保存工作并退出 Claude Code。继续？'), '确认账号切换', 'YesNo', 'Question')
    if ($answer -eq 'Yes') { Start-Action 'switch' $selected.Id {param($r) Show-Message $r} }
})
$window.FindName('BtnAdd').Add_Click({Save-AccountDialog})
$window.FindName('BtnRename').Add_Click({Save-AccountDialog})
$window.FindName('BtnShowAdd').Add_Click({Open-AccountDialog 'add'})
$window.FindName('DialogCancel').Add_Click({Close-AccountDialog})
$window.FindName('AccountList').AddHandler([Windows.Controls.Button]::ClickEvent,[Windows.RoutedEventHandler]{param($sender,$event)
    $button=$event.OriginalSource
    if ($button -is [Windows.Controls.Button] -and $button.Tag -eq 'RenameAccount') {
        Open-AccountDialog 'rename' $button.DataContext
        $event.Handled=$true
    }
})
$window.Add_PreviewKeyDown({
    if ($script:dialogMode) {
        if ($_.Key -eq 'Escape') {Close-AccountDialog;$_.Handled=$true}
        elseif ($_.Key -eq 'Return') {Save-AccountDialog;$_.Handled=$true}
    } elseif ($_.Key -eq 'Escape' -and $window.FindName('DetailsPanel').Visibility -eq 'Visible') {Show-Details $false;$_.Handled=$true}
})
$window.FindName('BtnRefresh').Add_Click({ Start-Action 'status' '' {param($r) Show-Accounts $r; $window.FindName('StatusText').Text='账号列表已刷新'; $window.FindName('Hint').Text='没有替换 Claude 数据。'} })
$window.FindName('BtnRestore').Add_Click({
    $answer=[Windows.MessageBox]::Show($window,'将先保留现有数据，再恢复上次切换前的副本。请先保存工作并退出 Claude Code。继续？','恢复数据','YesNo','Question')
    if ($answer -eq 'Yes') { Start-Action 'restore' '' {param($r) Show-Message $r} }
})
$window.FindName('BtnFolder').Add_Click({ [void](New-Item -ItemType Directory -Path $StateRoot -Force); Start-Process explorer.exe -ArgumentList ('"'+$StateRoot+'"') })
$navIndexes=@{NavOverview=0;NavAccounts=1;NavNetwork=2;NavFingerprint=3;NavReports=4;NavAbout=5;NavEnvironment=6}
foreach ($name in $navIndexes.Keys) {
    $window.FindName($name).Add_Checked({param($sender,$event) Show-Page $navIndexes[$sender.Name]})
}
$window.Add_SizeChanged({Update-Narrow $window.ActualWidth})
$window.FindName('StateRootText').Text=$StateRoot
Set-BasicTiles @(ConvertTo-CheckItems @('Claude 桌面版','代理内核','TUN 网卡','本地代理端口','代理 HTTPS 出口' | ForEach-Object {[pscustomobject]@{Name=$_;State='unknown';Detail='尚未检查'}}))
Update-LaunchButton
Update-Narrow $window.Width
$window.FindName('HugIdle').Source=Get-HugBitmap 'pose-01.png'
$window.FindName('HugFinal').Source=Get-HugBitmap 'pose-15.png'
$window.FindName('SceneEmpty').Source=Get-HugBitmap 'background.png'
$hugVideo=Join-Path $hugAssets 'hug-motion.mp4'
if ([IO.File]::Exists($hugVideo)) {$hugMotion.Source=New-Object Uri $hugVideo}
Initialize-HugDust
Update-GlassSource
$window.FindName('HugStage').Add_SizeChanged({Update-HugLayout})
$window.Add_LayoutUpdated({Update-GlassClip})
$window.FindName('BtnDetails').Add_Click({Show-Details ($window.FindName('DetailsPanel').Visibility -ne 'Visible')})
$window.FindName('BtnDetailsClose').Add_Click({Show-Details $false})


$window.FindName('BtnGoEnvironment').Add_Click({Show-Page 6})
$window.FindName('BtnEnvironmentRead').Add_Click({Start-Action 'environment-read' '' {param($r) Show-EnvironmentPreferences $r; $window.FindName('StatusText').Text='已读取 Windows 当前设置，没有修改。'}})
$window.FindName('BtnTimezoneApply').Add_Click({Apply-EnvironmentChoice 'Timezone'})
$window.FindName('BtnFormatApply').Add_Click({Apply-EnvironmentChoice 'Format'})
$window.FindName('BtnLanguageApply').Add_Click({Apply-EnvironmentChoice 'Language'})
foreach ($kind in @('Timezone','Format','Language')) {$window.FindName($kind+'Choice').Add_SelectionChanged({Update-EnvironmentButtons})}
$window.FindName('BtnWindowsLanguage').Add_Click({Start-Process 'ms-settings:regionlanguage'})
$window.FindName('BtnWindowsTime').Add_Click({Start-Process 'ms-settings:dateandtime'})
foreach ($name in @('BtnChromeLanguages','BtnChromeFonts','BtnChromeIpPure')) {
    $window.FindName($name).Add_Click({param($sender)
        try {
            Open-ChromePage ([string]$sender.Tag)
            $window.FindName('ChromeEnvironmentFeedback').Text='已请求 Chrome 打开页面。请确认右上角的配置文件；设置或重新扫描后的实际结果以 Chrome 为准。'
        } catch {$window.FindName('ChromeEnvironmentFeedback').Text=$_.Exception.Message}
    })
}

function Set-WarmCaption {
    # Windows 11 draws the native title bar in the preview's dark brown; older systems keep their default caption.
    # A dynamic P/Invoke avoids compiling C# with Add-Type, which would slow every start by seconds.
    try {
        $builder=[AppDomain]::CurrentDomain.DefineDynamicAssembly((New-Object Reflection.AssemblyName 'LauncherCaption'),[Reflection.Emit.AssemblyBuilderAccess]::Run)
        $type=$builder.DefineDynamicModule('LauncherCaption').DefineType('LauncherCaption.Dwm','Public, Class')
        $method=$type.DefinePInvokeMethod('DwmSetWindowAttribute','dwmapi.dll',[Reflection.MethodAttributes]'Public, Static, PinvokeImpl',[Reflection.CallingConventions]::Standard,[int],[Type[]]@([IntPtr],[int],[int].MakeByRefType(),[int]),[Runtime.InteropServices.CallingConvention]::Winapi,[Runtime.InteropServices.CharSet]::Unicode)
        $method.SetImplementationFlags([Reflection.MethodImplAttributes]::PreserveSig)
        $dwm=$type.CreateType()
        $handle=(New-Object Windows.Interop.WindowInteropHelper $window).Handle
        # 20 dark caption buttons, 34 border #5A4436, 35 caption #45352E, 36 title text #E9D9C4 (COLORREF is 0x00BBGGRR).
        foreach ($pair in @(@(20,1),@(34,0x0036445A),@(35,0x002E3545),@(36,0x00C4D9E9))) {
            $value=[int]$pair[1]
            [void]$dwm::DwmSetWindowAttribute($handle,[int]$pair[0],[ref]$value,4)
        }
    } catch {}
}
$window.Add_SourceInitialized({
    Set-WarmCaption
    # Center the complete native window inside this monitor's work area at its active DPI.
    $source=[Windows.PresentationSource]::FromVisual($window)
    [TaskbarIdentity]::ConfigureWindow($source.Handle,$PSScriptRoot)
    $window.Add_Closing({
        if (-not $_.Cancel) {[TaskbarIdentity]::ClearWindow((New-Object Windows.Interop.WindowInteropHelper $window).Handle)}
    })
    $area=[Windows.Forms.Screen]::FromHandle($source.Handle).WorkingArea
    $size=$source.CompositionTarget.TransformFromDevice.Transform([Windows.Vector]::new($area.Width,$area.Height))
    $origin=$source.CompositionTarget.TransformFromDevice.Transform([Windows.Point]::new($area.Left,$area.Top))
    $window.MinWidth=[Math]::Min($window.MinWidth,$size.X-32)
    $window.MinHeight=[Math]::Min($window.MinHeight,$size.Y-32)
    $window.Width=[Math]::Min($window.Width,$size.X-32)
    $window.Height=[Math]::Min($window.Height,$size.Y-32)
    $window.Left=$origin.X+($size.X-$window.Width)/2
    $window.Top=$origin.Y+($size.Y-$window.Height)/2
})
$window.Add_ContentRendered({
    Initialize-GuardTray
    Update-GuardDisplay
    $guardTimer.Start()
    Load-LatestReports
    Open-HugMotion
    Start-Action 'guard-start' '' { param($r)
        $window.FindName('StatusText').Text='全时段守护已启动，覆盖 Claude Desktop 和 Claude Code。'
        Show-Accounts $r
        $window.FindName('Hint').Text='正常启动不会复制或替换登录数据。'
    }
    if ($StartHidden) {$window.ShowInTaskbar=$false; $window.WindowState='Minimized'}
})
$window.Add_Closing({
    if ($script:operation) {
        $_.Cancel=$true
        $window.FindName('Hint').Text='当前操作尚未完成，请等待后关闭。'
    } elseif ($script:tray -and -not $script:exitInterface) {
        $_.Cancel=$true
        $window.ShowInTaskbar=$false
        $window.WindowState='Minimized'
    }
})
$window.Add_Closed({if ($script:guardAlert) {$script:guardAlert.Close()};$guardTimer.Stop();$hugTimer.Stop();$sceneTimer.Stop();$hugMotion.Close();if ($script:tray) {$script:tray.Dispose()}})
[void]$window.ShowDialog()
